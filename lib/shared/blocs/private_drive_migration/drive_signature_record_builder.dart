import 'dart:typed_data';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/drive_signature.dart';
import 'package:ardrive/entities/drive_signature_type.dart';
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart' show Cipher;
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:collection/collection.dart';

/// Builds the drive-signature record the v1 drive migration posts, and
/// refuses to build one it can't prove.
///
/// The record holds the drive's v1 wallet signature encrypted under the
/// drive's v2 key, so wallets that no longer offer the v1 signature can still
/// open the drive. It is permanent, and every reader - web, core-js, the CLI,
/// desktop - takes only the newest record for a drive. A record encrypted
/// under the wrong key therefore breaks the drive in every app, and nothing
/// can take it back. So nothing here trusts the session's password:
///
/// 1. The drive's newest metadata must decrypt with [currentKey], the key
///    the device already holds for it, right now.
/// 2. The password bytes used are the ones that, with a fresh v1 signature,
///    reproduce [currentKey] exactly. A password that opens some other drive
///    does not.
/// 3. The wallet's v2 signature must be the same twice: every reader signs v2
///    afresh, so one that varies would make a record nobody can open.
/// 4. The record is read back - decrypted with the v2 key, the v1 key derived
///    from what comes out - and that key must equal [currentKey] and open the
///    drive. This catches an encryption mistake; it is step 3 that stands in
///    for a reader's own fresh signature.
///
/// Any check that fails, or throws, returns null, and nothing is posted.
/// Why [DriveSignatureRecordBuilder.build] last built nothing.
enum DriveSignatureRecordRefusal {
  /// None of the passwords given makes the drive's key. The drive's own
  /// password, asked for, may.
  unknownPassword,

  /// Anything else: nothing a password can change.
  other,
}

class DriveSignatureRecordBuilder {
  DriveSignatureRecordBuilder({
    required ArDriveCrypto crypto,
    required ArweaveService arweave,
    required DriveUnlocker unlocker,
  })  : _crypto = crypto,
        _arweave = arweave,
        _unlocker = unlocker;

  final ArDriveCrypto _crypto;
  final ArweaveService _arweave;
  final DriveUnlocker _unlocker;

  /// Why the last [build] returned null, or null when it built a record.
  DriveSignatureRecordRefusal? lastRefusal;

  /// The record for [driveId], or null when it can't be proven.
  ///
  /// [passwordInfos] are the candidate password bytes, most likely first: the
  /// ones proven on this drive this session, then the sign-in password's.
  Future<DriveSignatureEntity?> build({
    required Wallet wallet,
    required String driveId,
    required DriveKey currentKey,
    required List<List<int>> passwordInfos,
  }) async {
    lastRefusal = DriveSignatureRecordRefusal.other;
    try {
      final record = await _build(
        wallet: wallet,
        driveId: driveId,
        currentKey: currentKey,
        passwordInfos: passwordInfos,
      );
      if (record != null) {
        lastRefusal = null;
      }
      return record;
    } catch (e) {
      logger.w('Not migrating $driveId: a check could not be completed: $e');
      lastRefusal = DriveSignatureRecordRefusal.other;
      return null;
    }
  }

  Future<DriveSignatureEntity?> _build({
    required Wallet wallet,
    required String driveId,
    required DriveKey currentKey,
    required List<List<int>> passwordInfos,
  }) async {
    final owner = await wallet.getAddress();
    final currentKeyBytes = await currentKey.key.extractBytes();

    // 1. The key the device holds must open the drive as it is now.
    final driveTx = await _arweave.getLatestDriveTx(driveId, owner);

    if (driveTx == null) {
      logger.w('Not migrating $driveId: its metadata was not found');
      return null;
    }

    if (DriveSignatureType.fromString(
            driveTx.getTag(EntityTag.signatureType) ?? '1') !=
        DriveSignatureType.v1) {
      logger.w('Not migrating $driveId: it is not a v1 drive');
      return null;
    }

    final data = await _arweave.getEntityDataBytes(driveTx.id);

    if (await _unlocker.openWithKey(driveTx, data, currentKey) == null) {
      logger.w('Not migrating $driveId: the key held does not open it');
      return null;
    }

    // 2. Which password made that key. The v1 signature is kept for the
    //    session, so asking for the drive's password and trying again does
    //    not ask the wallet again.
    final v1Signature =
        _unlocker.session.signature(owner, driveId, DriveSignatureType.v1) ??
            await _crypto.walletSignatureForDrive(
                wallet, driveId, DriveSignatureType.v1);
    _unlocker.session
        .rememberSignature(owner, driveId, DriveSignatureType.v1, v1Signature);

    List<int>? info;

    for (final candidate in passwordInfos) {
      final derived = await _crypto
          .driveKeyFromSignature(v1Signature, candidate, generated: true);

      if (_same(await derived.key.extractBytes(), currentKeyBytes)) {
        info = candidate;
        break;
      }
    }

    if (info == null) {
      logger.w('Not migrating $driveId: no known password makes its key');
      lastRefusal = DriveSignatureRecordRefusal.unknownPassword;
      return null;
    }

    // 3. Encrypt the v1 signature under that password's v2 key - but only if
    //    the wallet's v2 signature is the same every time. Every reader signs
    //    v2 afresh to open the record, so a wallet whose v2 signature varies
    //    (some hardware and smart-contract setups) would post a record no
    //    reader can ever open. Checked against the one this session already
    //    holds for the drive, or against a second signature.
    final v2Signature = await _crypto.walletSignatureForDrive(
        wallet, driveId, DriveSignatureType.v2);
    final v2Again =
        _unlocker.session.signature(owner, driveId, DriveSignatureType.v2) ??
            await _crypto.walletSignatureForDrive(
                wallet, driveId, DriveSignatureType.v2);

    if (!_same(v2Signature, v2Again)) {
      logger.w('Not migrating $driveId: the wallet\'s v2 signature varies');
      return null;
    }
    final driveKeyV2 = await _crypto.driveKeyFromSignature(v2Signature, info,
        generated: false);
    final box = await _crypto.encrypt(v1Signature, driveKeyV2.key);

    final record = DriveSignatureEntity(
      driveId: driveId,
      signatureFormat: '1',
      cipher: Cipher.aes256gcm,
      cipherIv: utils.encodeBytesToBase64(box.nonce),
      data: Uint8List.fromList(box.concatenation(nonce: false)),
    );

    // 5. Read it back from the record alone.
    final readerKeyV2 = await _crypto.driveKeyFromSignature(v2Signature, info,
        generated: false);
    final readBack =
        await _crypto.decryptStoredDriveSignature(record, readerKeyV2.key);

    if (!_same(readBack, v1Signature)) {
      logger.w('Not migrating $driveId: the record did not read back');
      return null;
    }

    final readerKey =
        await _crypto.driveKeyFromSignature(readBack, info, generated: false);

    if (!_same(await readerKey.key.extractBytes(), currentKeyBytes) ||
        await _unlocker.openWithKey(driveTx, data, readerKey) == null) {
      logger.w('Not migrating $driveId: the record does not open the drive');
      return null;
    }

    return record;
  }

  static bool _same(List<int> a, List<int> b) =>
      const ListEquality<int>().equals(a, b);
}

import 'dart:typed_data';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/drive_signature.dart';
import 'package:ardrive/entities/drive_signature_type.dart';
import 'package:ardrive/entities/entities.dart' hide Cipher;
import 'package:ardrive/locked_drives/domain/drive_password_info.dart';
import 'package:ardrive/locked_drives/domain/drive_unlock_session.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart' show Cipher;
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:cryptography/cryptography.dart' hide Cipher;

/// Why a password, or a key, didn't open a drive.
enum DriveUnlockFailure {
  /// AES-GCM authentication failed: the key is wrong, so the password is.
  /// The only failure the app may call "Wrong password".
  wrongPassword,

  /// The wallet's prompt was cancelled: the user said no.
  walletDeclined,

  /// The wallet couldn't sign for another reason (it is locked, disconnected,
  /// or errored).
  walletFailed,

  /// Anything else: the drive's metadata or its signature record couldn't be
  /// read, or what decrypted couldn't be read as a drive.
  unavailable,
}

/// One attempt to open a drive: the key and the drive it opened, or why not.
class DriveKeyAttempt {
  const DriveKeyAttempt.opened({
    required DriveKey this.key,
    required DriveEntity this.entity,
    this.passwordInfo,
  }) : failure = null;

  const DriveKeyAttempt.failed(DriveUnlockFailure this.failure)
      : key = null,
        entity = null,
        passwordInfo = null;

  final DriveKey? key;

  /// The drive's newest metadata, decrypted with [key].
  final DriveEntity? entity;

  /// The password bytes that made [key], when a password did. Null when a key
  /// the device already held opened the drive.
  final List<int>? passwordInfo;

  final DriveUnlockFailure? failure;

  bool get opened => key != null;
}

/// The outcome of the unlock dialog: the drives it opened, or why the one
/// asked for stayed locked.
class DriveUnlockResult {
  const DriveUnlockResult.opened(this.openedDriveIds) : failure = null;

  const DriveUnlockResult.failed(DriveUnlockFailure this.failure)
      : openedDriveIds = const [];

  /// The drive asked for first, then any others the same password opened.
  final List<String> openedDriveIds;
  final DriveUnlockFailure? failure;

  bool get opened => openedDriveIds.isNotEmpty;
}

/// Thrown by [DriveUnlocker.openWithKey] when a drive's metadata
/// authenticated but can't be read as a drive: not a password problem.
class DriveUnreadableException implements Exception {
  const DriveUnreadableException(this.driveId);

  final String? driveId;

  @override
  String toString() => 'DriveUnreadableException($driveId)';
}

/// Whether [error], thrown by a wallet asked to sign, means the user said no.
///
/// Wallets report a cancelled prompt as an error with no shared type: Wander
/// says "User cancelled the auth", others "User rejected the request" or
/// "denied". A heuristic, so anything it doesn't recognise is reported as a
/// wallet that couldn't sign, which at worst shows a message for a cancel.
bool isWalletCancellation(Object error) => RegExp(
      r'cancel|reject|denied|declin|closed|dismiss|abort',
      caseSensitive: false,
    ).hasMatch(error.toString());

/// How many new wallet prompts one pass over several drives may cost.
///
/// For a wallet that asks the user for every signature (Wander): a drive
/// whose signature is already held costs nothing; each one that isn't takes
/// one from here, and once it is spent the remaining drives are left locked
/// rather than prompted for. One per sign-in, discovery pass or unlock.
class WalletPromptBudget {
  WalletPromptBudget(this.remaining);

  /// How many prompts a pass may cost a prompting wallet.
  static const perPass = 3;

  int remaining;

  bool take() {
    if (remaining <= 0) return false;
    remaining--;
    return true;
  }
}

/// How many times the unlock dialog's metadata read is tried.
const unlockMaxRetries = 3;

/// Reads a drive key this device keeps for [driveId], or null.
typedef StoredDriveKeyReader = Future<DriveKey?> Function(String driveId);

/// Opens private drives: finds a key, proves it on the drive's metadata, and
/// keeps it.
///
/// One rule everywhere: a key is kept - in memory, on the device, or used to
/// write anything - only once it has decrypted the drive's metadata. Deriving
/// a key proves nothing, because every password derives one.
class DriveUnlocker {
  DriveUnlocker({
    required ArDriveCrypto crypto,
    required ArweaveService arweave,
    required DriveDao driveDao,
    required DriveUnlockSession session,
  })  : _crypto = crypto,
        _arweave = arweave,
        _driveDao = driveDao,
        _session = session;

  final ArDriveCrypto _crypto;
  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final DriveUnlockSession _session;

  DriveUnlockSession get session => _session;

  /// Decrypts the drive metadata [data] of [driveTx] with [key].
  ///
  /// Null when the key is wrong: AES-GCM authentication failed. Throws
  /// [DriveUnreadableException] for anything else, so a corrupt or unexpected
  /// entity is never reported as a wrong password.
  Future<DriveEntity?> openWithKey(
    TransactionCommonMixin driveTx,
    Uint8List data,
    DriveKey key,
  ) async {
    final driveId = driveTx.getTag(EntityTag.driveId);
    final cipher = driveTx.getTag(EntityTag.cipher);
    final cipherIv = driveTx.getTag(EntityTag.cipherIv);

    if (cipher == Cipher.aes256gcm && cipherIv != null) {
      try {
        await _crypto.decrypt(
            data, key.key, utils.decodeBase64ToBytes(cipherIv));
      } on SecretBoxAuthenticationError {
        return null;
      } catch (_) {
        throw DriveUnreadableException(driveId);
      }
    }

    try {
      return await DriveEntity.fromTransaction(driveTx, _crypto, data, key.key);
    } on EntityTransactionParseException {
      if (cipher == Cipher.aes256gcm) {
        throw DriveUnreadableException(driveId);
      }

      // AES-CTR carries no authentication tag, so unreadable output is the
      // only sign of a wrong key. No ArDrive app writes drive metadata this
      // way; this keeps an old one from reading as "couldn't reach".
      return null;
    }
  }

  /// Tries [password] on the drive whose newest metadata is [driveTx] and
  /// [data].
  ///
  /// 1. The signature type comes from the drive's tags; none means v1. A v1
  ///    drive uses its stored drive-signature record when it has one.
  /// 2. The key is derived exactly as [ArDriveCrypto.deriveDriveKey] derives
  ///    it, from a wallet signature kept for the session, so the wallet is
  ///    asked at most once per drive.
  /// 3. It is proven by decrypting the metadata. A password with non-ASCII
  ///    characters is also tried in core-js's double encoding - see
  ///    [drivePasswordInfos].
  ///
  /// When [mayAskWallet] is false and the user cancelled this drive's wallet
  /// prompt earlier in the session, the wallet is not asked again.
  ///
  /// Keeps nothing except the signature and, on success, the password bytes
  /// for the v1 migration (both in [DriveUnlockSession]).
  Future<DriveKeyAttempt> tryPassword({
    required Wallet wallet,
    required TransactionCommonMixin driveTx,
    required Uint8List data,
    required String password,
    bool forSync = false,
    bool mayAskWallet = true,
    WalletPromptBudget? promptBudget,
  }) async {
    final driveId = driveTx.getTag(EntityTag.driveId)!;
    final signatureType = DriveSignatureType.fromString(
        driveTx.getTag(EntityTag.signatureType) ?? '1');
    final owner = await wallet.getAddress();

    DriveSignatureEntity? record;

    if (signatureType == DriveSignatureType.v1) {
      try {
        record = forSync
            ? await _arweave.getDriveSignatureForDriveOnSync(wallet, driveId)
            : await _arweave.getDriveSignatureForDrive(wallet, driveId);
      } catch (e) {
        logger.w('Could not read the drive signature for $driveId: $e');
        return const DriveKeyAttempt.failed(DriveUnlockFailure.unavailable);
      }
    }

    // A stored v1 signature is encrypted under the drive's v2 key, so the
    // wallet signs the v2 message for it.
    final signingType = record != null ? DriveSignatureType.v2 : signatureType;

    var signature = _session.signature(owner, driveId, signingType);

    if (signature == null) {
      if (!mayAskWallet && _session.walletDeclined(owner, driveId)) {
        return const DriveKeyAttempt.failed(DriveUnlockFailure.walletDeclined);
      }

      // Out of prompts for this pass: left locked, and not asked by later
      // background passes either - only when the user acts (Unlock, or a
      // sync they start). Otherwise every pass would ask three more.
      if (promptBudget != null && !promptBudget.take()) {
        _session.markWalletDeclined(owner, driveId);
        return const DriveKeyAttempt.failed(DriveUnlockFailure.walletDeclined);
      }

      try {
        signature =
            await _crypto.walletSignatureForDrive(wallet, driveId, signingType);
      } catch (e) {
        logger.w('The wallet did not sign for $driveId: $e');
        // Either way a background pass does not ask again this session.
        _session.markWalletDeclined(owner, driveId);
        return DriveKeyAttempt.failed(
          isWalletCancellation(e)
              ? DriveUnlockFailure.walletDeclined
              : DriveUnlockFailure.walletFailed,
        );
      }

      _session.rememberSignature(owner, driveId, signingType, signature);
    }

    for (final info in drivePasswordInfos(password)) {
      final DriveKey key;

      if (record != null) {
        final driveKeyV2 = await _crypto.driveKeyFromSignature(signature, info,
            generated: false);

        final Uint8List v1Signature;
        try {
          v1Signature =
              await _crypto.decryptStoredDriveSignature(record, driveKeyV2.key);
        } on SecretBoxAuthenticationError {
          continue;
        } catch (e) {
          logger.w('Could not read the drive signature for $driveId: $e');
          return const DriveKeyAttempt.failed(DriveUnlockFailure.unavailable);
        }

        key = await _crypto.driveKeyFromSignature(v1Signature, info,
            generated: false);
      } else {
        key = await _crypto.driveKeyFromSignature(signature, info,
            generated: true);
      }

      final DriveEntity? entity;
      try {
        entity = await openWithKey(driveTx, data, key);
      } on DriveUnreadableException {
        return const DriveKeyAttempt.failed(DriveUnlockFailure.unavailable);
      }

      if (entity != null) {
        _session.rememberProvenPasswordInfo(driveId, info);
        return DriveKeyAttempt.opened(
            key: key, entity: entity, passwordInfo: info);
      }
    }

    return const DriveKeyAttempt.failed(DriveUnlockFailure.wrongPassword);
  }

  /// Drive discovery's answer for one private drive.
  ///
  /// The keys the session already holds come first: the one in memory, then
  /// the one this device stored for the drive ([storedKey]). Only if neither
  /// opens it is [password] - the sign-in password - tried, which may ask the
  /// wallet. A drive whose prompt was cancelled this session is not asked
  /// again unless [mayAskWallet].
  ///
  /// A key that opens the drive goes into memory. One that doesn't is never
  /// kept: a wrong key in memory would be found first on every later pass.
  Future<DriveKeyAttempt> resolveForDiscovery({
    required Wallet wallet,
    required TransactionCommonMixin driveTx,
    required Uint8List data,
    required String password,
    StoredDriveKeyReader? storedKey,
    bool mayAskWallet = true,
    WalletPromptBudget? promptBudget,
  }) async {
    final driveId = driveTx.getTag(EntityTag.driveId)!;

    final inMemory = await _driveDao.getDriveKeyFromMemory(driveId);

    if (inMemory != null) {
      final entity = await _openOrNull(driveTx, data, inMemory);

      if (entity != null) {
        return DriveKeyAttempt.opened(key: inMemory, entity: entity);
      }
    }

    if (storedKey != null) {
      DriveKey? stored;

      try {
        stored = await storedKey(driveId);
      } catch (e) {
        logger.w('Could not read the stored key for $driveId: $e');
      }

      if (stored != null) {
        final entity = await _openOrNull(driveTx, data, stored);

        if (entity != null) {
          await _driveDao.putDriveKeyInMemory(
              driveID: driveId, driveKey: stored);
          return DriveKeyAttempt.opened(key: stored, entity: entity);
        }
      }
    }

    final attempt = await tryPassword(
      wallet: wallet,
      driveTx: driveTx,
      data: data,
      password: password,
      forSync: true,
      mayAskWallet: mayAskWallet,
      promptBudget: promptBudget,
    );

    if (attempt.opened) {
      await _driveDao.putDriveKeyInMemory(
          driveID: driveId, driveKey: attempt.key!);
    }

    return attempt;
  }

  Future<DriveEntity?> _openOrNull(
    TransactionCommonMixin driveTx,
    Uint8List data,
    DriveKey key,
  ) async {
    try {
      return await openWithKey(driveTx, data, key);
    } on DriveUnreadableException {
      return null;
    }
  }

  /// Unlocks [driveId] with [password], and with [tryOthers] every other
  /// locked drive the same password opens.
  ///
  /// The drive's newest metadata is read fresh, so a drive renamed since the
  /// list was read opens under its current name. Each drive that opens is kept
  /// the way an unlocked drive's key is kept - in memory and, under
  /// [profileKey], on its drive row - and leaves the locked list.
  ///
  /// The result is about [driveId]: if it stays locked nothing else is tried.
  /// The other drives are tried quietly. Their wallet is asked only if their
  /// signature isn't already held and their prompt wasn't cancelled.
  Future<DriveUnlockResult> unlock({
    required Wallet wallet,
    required SecretKey? profileKey,
    required String driveId,
    required String password,
    bool tryOthers = true,
  }) async {
    final owner = await wallet.getAddress();

    // The user asked for this drive, which is what lets its wallet prompt
    // come back after being cancelled.
    _session.forgetWalletDeclined(ownerAddress: owner, driveId: driveId);

    final first = await _unlockOne(
      wallet: wallet,
      ownerAddress: owner,
      profileKey: profileKey,
      driveId: driveId,
      password: password,
      mayAskWallet: true,
    );

    if (!first.opened) {
      return DriveUnlockResult.failed(first.failure!);
    }

    final opened = [driveId];

    if (tryOthers) {
      // The drive asked for may prompt; the others share a small budget, so
      // one password tried on many drives can't become a prompt per drive.
      final budget = wallet is ArConnectWallet
          ? WalletPromptBudget(WalletPromptBudget.perPass)
          : null;
      final others = [
        for (final drive in _session.currentLockedDrives)
          if (drive.ownerAddress == owner && drive.driveId != driveId)
            drive.driveId,
      ];

      for (final other in others) {
        final attempt = await _unlockOne(
          wallet: wallet,
          ownerAddress: owner,
          profileKey: profileKey,
          driveId: other,
          password: password,
          mayAskWallet: false,
          promptBudget: budget,
        );

        if (attempt.opened) {
          opened.add(other);
        }
      }
    }

    return DriveUnlockResult.opened(opened);
  }

  Future<DriveKeyAttempt> _unlockOne({
    required Wallet wallet,
    required String ownerAddress,
    required SecretKey? profileKey,
    required String driveId,
    required String password,
    required bool mayAskWallet,
    WalletPromptBudget? promptBudget,
  }) async {
    final TransactionCommonMixin? driveTx;
    final Uint8List data;

    try {
      // A few quick tries, not the eight a sync makes: somebody is watching
      // the dialog, and "Couldn't reach the network" after a minute and a
      // half of backoff is a dialog that looks frozen.
      driveTx = await _arweave.getLatestDriveTx(
        driveId,
        ownerAddress,
        maxRetries: unlockMaxRetries,
      );

      if (driveTx == null) {
        return const DriveKeyAttempt.failed(DriveUnlockFailure.unavailable);
      }

      data = await _arweave.getEntityDataBytes(driveTx.id);
    } catch (e) {
      logger.w('Could not read the metadata of $driveId: $e');
      return const DriveKeyAttempt.failed(DriveUnlockFailure.unavailable);
    }

    final attempt = await tryPassword(
      wallet: wallet,
      driveTx: driveTx,
      data: data,
      password: password,
      mayAskWallet: mayAskWallet,
      promptBudget: promptBudget,
    );

    if (attempt.opened) {
      await _keep(attempt, profileKey);
    }

    return attempt;
  }

  /// Keeps a proven key the way an unlocked drive's key is kept today: in the
  /// memory vault, and wrapped under the profile key on the drive's row.
  Future<void> _keep(DriveKeyAttempt attempt, SecretKey? profileKey) async {
    final entity = attempt.entity!;
    final driveId = entity.id!;

    await _driveDao.putDriveKeyInMemory(
        driveID: driveId, driveKey: attempt.key!);

    await _driveDao.writeDriveEntity(
      name: entity.name!,
      entity: entity,
      driveKey: attempt.key,
      profileKey: profileKey,
    );

    _session.markUnlocked(driveId);
  }
}

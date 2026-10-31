import 'dart:typed_data';

import 'package:collection/collection.dart' show IterableExtension;

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/drive_signature.dart';
import 'package:ardrive/entities/drive_signature_type.dart';
import 'package:ardrive/entities/entities.dart' hide Cipher;
import 'package:ardrive/locked_drives/domain/drive_password_info.dart';
import 'package:ardrive/locked_drives/domain/drive_password_order.dart';
import 'package:ardrive/locked_drives/domain/drive_unlock_session.dart';
import 'package:ardrive/locked_drives/domain/locked_drive.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/services/arconnect/arconnect_prompt.dart';
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

  /// Not tried: this device was told not to keep the drive's key ("Remember
  /// on this device" off, or "Forget on this device"), so it is not opened
  /// on its own. It stays locked until the person unlocks it.
  notTried,
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
/// Wallets report a cancelled prompt as an error with no shared type. Wander
/// throws "User cancelled the AuthRequest" when its popup is cancelled and
/// "User rejected the signature request" when a signature is refused
/// (`src/utils/auth/auth.constants.ts`, `signature.background.ts`); other
/// wallets say "User rejected the request" or "canceled". Only those words
/// count: a real failure such as "message port closed" or an aborted request
/// is reported as a wallet that couldn't sign, so the user is told.
bool isWalletCancellation(Object error) =>
    RegExp(r'cancel|reject', caseSensitive: false).hasMatch(error.toString());

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

/// What became of asking the wallet to sign several drives in one approval.
/// See [DriveUnlocker.signInOneApproval].
enum DriveSignatureBatch {
  /// Nobody was asked: the wallet can't batch-sign, there were fewer than
  /// two drives to sign for, or the pass had no prompt left. Go on drive by
  /// drive.
  notAsked,

  /// Every drive's v2 signature is held now, each checked to be the one its
  /// drive key comes from.
  signed,

  /// The person said no, or chose not to wait for Wander. One cancel for
  /// every drive in it: each is marked declined and stays locked, and is not
  /// asked for again one by one.
  declined,

  /// Wander was asked, but the batch can't be used: it refused (a hardware
  /// wallet), failed, or some of its signatures weren't the ones drive keys
  /// come from. Any that were are kept. Go on drive by drive.
  unusable,
}

/// A private drive's newest metadata transaction and that metadata.
typedef DriveMetadata = ({TransactionCommonMixin tx, Uint8List data});

/// Whether [error], thrown while asking Wander, means the person said no:
/// they cancelled its prompt, or chose not to wait when it didn't answer.
bool _personDeclined(Object error) =>
    error is ArConnectUnavailableException || isWalletCancellation(error);

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

  /// The most drives one approval signs for. Wander caps a batch at 200 KB
  /// of item data, about 9,000 drives; any past this go drive by drive.
  static const maxDrivesPerBatch = 2000;

  /// Gets the v2 wallet signatures of [driveIds] that the session doesn't
  /// hold yet in one Wander approval (`batchSignDataItem`), so a password
  /// can then be tried on all of those drives without asking again.
  ///
  /// Only for a Wander that can, with at least two drives to sign for; a
  /// batch takes one prompt from [promptBudget]. It is the only prompt.
  ///
  /// Every signature that comes back is checked on its own
  /// ([ArDriveCrypto.isDriveSignature]): RSA-PSS with no salt, over the item
  /// asked for, against the wallet's public key. With no salt there is one
  /// valid signature per item, so one that passes is the one every ArDrive
  /// app derives that drive's key from. Only those are kept, for the session
  /// like any other. If any fails (a Wander build that ignores `saltLength`,
  /// items out of order, a hardware wallet), the batch is not tried again
  /// this session and the drives whose signature failed go one by one.
  ///
  /// With [quiet] (a pass nobody asked for drive by drive: discovery), the
  /// batch stays quiet after the person cancelled "Wander needs your
  /// permission again"; see [ArConnectPrompt.quietAfterCancel]. A batch that
  /// carries a drive the person asked for, or the sign-in check, is not.
  Future<DriveSignatureBatch> signInOneApproval({
    required Wallet wallet,
    required List<String> driveIds,
    WalletPromptBudget? promptBudget,
    bool quiet = false,
  }) async {
    if (wallet is! ArConnectWallet || !wallet.canBatchSign) {
      return DriveSignatureBatch.notAsked;
    }

    final owner = await wallet.getAddress();

    if (_session.batchSigningUnusable(owner)) {
      return DriveSignatureBatch.notAsked;
    }

    final needed = {
      for (final driveId in driveIds)
        if (_session.signature(owner, driveId, DriveSignatureType.v2) == null)
          driveId,
    }.take(maxDrivesPerBatch).toList();

    // One drive costs one prompt either way.
    if (needed.length < 2) {
      return DriveSignatureBatch.notAsked;
    }

    if (promptBudget != null && !promptBudget.take()) {
      return DriveSignatureBatch.notAsked;
    }

    final List<Uint8List> signatures;
    try {
      Future<List<Uint8List>> sign() =>
          _crypto.batchWalletSignaturesForDrives(wallet, needed);
      signatures =
          quiet ? await ArConnectPrompt.quietAfterCancel(sign) : await sign();
    } catch (e) {
      if (_personDeclined(e)) {
        logger.i('The batch of drive signatures was declined: $e');
        for (final driveId in needed) {
          _session.markWalletDeclined(owner, driveId);
        }
        return DriveSignatureBatch.declined;
      }

      logger.w('Could not sign the drives in one approval: $e');
      _session.markBatchSigningUnusable(owner);
      return DriveSignatureBatch.unusable;
    }

    final publicKey = await wallet.getOwner();
    var allValid = true;

    for (var i = 0; i < needed.length; i++) {
      if (await _crypto.isDriveSignature(
          owner: publicKey, driveId: needed[i], signature: signatures[i])) {
        _session.rememberSignature(
            owner, needed[i], DriveSignatureType.v2, signatures[i]);
      } else {
        allValid = false;
      }
    }

    if (!allValid) {
      logger.w('Wander signed some drives in its batch with a signature no '
          'drive key comes from: those are asked for one by one');
      _session.markBatchSigningUnusable(owner);
      return DriveSignatureBatch.unusable;
    }

    return DriveSignatureBatch.signed;
  }

  /// Whether [driveId]'s key comes from its v2 signature: a v2 drive, or a
  /// v1 drive with a stored drive-signature record (encrypted under its v2
  /// key). Only those belong in a batch: a v1 drive without a record needs
  /// its own v1 signature, which a batch can't give.
  ///
  /// The record lookup is the one [tryPassword] makes for a v1 drive anyway,
  /// and is cached for the session, so asking here first adds no request.
  /// A lookup that fails leaves the drive out; its own attempt reports it.
  Future<bool> opensWithV2Signature({
    required Wallet wallet,
    required String driveId,
    required DriveSignatureType signatureType,
    bool forSync = false,
  }) async {
    if (signatureType != DriveSignatureType.v1) return true;

    try {
      final record = forSync
          ? await _arweave.getDriveSignatureForDriveOnSync(wallet, driveId)
          : await _arweave.getDriveSignatureForDrive(wallet, driveId);
      return record != null;
    } catch (e) {
      logger.w('Could not read the drive signature for $driveId: $e');
      return false;
    }
  }

  /// Drive discovery's one approval, before it tries a password on
  /// [drives] one by one: [signInOneApproval] for the drives that would
  /// otherwise ask the wallet. Those are the ones with no key in memory or
  /// stored on this device ([storedKey]), no signature held, no prompt
  /// cancelled this session, and not forgotten on this device: a forgotten
  /// drive is opened only by the person, never signed for on its behalf.
  Future<DriveSignatureBatch> signForDiscovery({
    required Wallet wallet,
    required List<DriveMetadata> drives,
    StoredDriveKeyReader? storedKey,
    WalletPromptBudget? promptBudget,
  }) async {
    if (wallet is! ArConnectWallet || !wallet.canBatchSign) {
      return DriveSignatureBatch.notAsked;
    }

    final owner = await wallet.getAddress();
    final forgotten = await _driveDao.forgottenDriveIds();
    final pending = <DriveMetadata>[];

    for (final drive in drives) {
      final driveId = drive.tx.getTag(EntityTag.driveId);
      if (driveId == null ||
          forgotten.contains(driveId) ||
          _session.holdsSignatureFor(owner, driveId) ||
          _session.walletDeclined(owner, driveId) ||
          await _driveDao.getDriveKeyFromMemory(driveId) != null) {
        continue;
      }

      if (storedKey != null) {
        try {
          if (await storedKey(driveId) != null) continue;
        } catch (_) {
          // Unreadable: resolving the drive says so.
        }
      }

      if (!await opensWithV2Signature(
        wallet: wallet,
        driveId: driveId,
        signatureType: _signatureTypeOf(drive.tx),
        forSync: true,
      )) {
        continue;
      }

      pending.add(drive);
    }

    final createdAt = _arweave.cachedUserDriveCreationTimes(owner);
    pending.sort((a, b) => compareForPasswordTries(
          a.tx,
          b.tx,
          (tx) => createdAt[tx.getTag(EntityTag.driveId)] ?? _commitTime(tx),
        ));

    return signInOneApproval(
      wallet: wallet,
      driveIds: [
        for (final drive in pending) drive.tx.getTag(EntityTag.driveId)!,
      ],
      promptBudget: promptBudget,
      quiet: true,
    );
  }

  static DriveSignatureType _signatureTypeOf(TransactionCommonMixin tx) =>
      DriveSignatureType.fromString(tx.getTag(EntityTag.signatureType) ?? '1');

  static DateTime _commitTime(TransactionCommonMixin tx) {
    try {
      return tx.getCommitTime();
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

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
    // No password, as for someone who signed in with a browser wallet and
    // hasn't given one this session: nothing to try, and the wallet is not
    // asked for a signature that could open nothing. No drive is made with
    // an empty password.
    if (password.isEmpty) {
      return const DriveKeyAttempt.failed(DriveUnlockFailure.wrongPassword);
    }

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
        // A pass over several drives stays quiet after the person cancelled
        // "Wander needs your permission again"; see
        // [ArConnectPrompt.quietAfterCancel].
        final Uint8List signed = promptBudget != null
            ? await ArConnectPrompt.quietAfterCancel(() =>
                _crypto.walletSignatureForDrive(wallet, driveId, signingType))
            : await _crypto.walletSignatureForDrive(
                wallet, driveId, signingType);
        signature = signed;
      } catch (e) {
        logger.w('The wallet did not sign for $driveId: $e');
        // Either way a background pass does not ask again this session.
        _session.markWalletDeclined(owner, driveId);
        // Cancel on ArDrive's own "Wander didn't answer" prompt: the person
        // gave up on Wander for now, so the rest of this pass asks it nothing
        // either, rather than a Cancel per drive.
        // A Wander reconnected on another wallet ends the pass the same way:
        // nothing more may be signed with it.
        final gaveUp = e is ArConnectUnavailableException ||
            e is ArConnectWalletMismatchException;
        if (gaveUp) promptBudget?.remaining = 0;
        return DriveKeyAttempt.failed(
          gaveUp || isWalletCancellation(e)
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
  /// again unless [mayAskWallet]. A [forgotten] drive gets only its key in
  /// memory: see [DriveUnlockFailure.notTried].
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
    bool forgotten = false,
  }) async {
    final driveId = driveTx.getTag(EntityTag.driveId)!;

    final inMemory = await _driveDao.getDriveKeyFromMemory(driveId);

    if (inMemory != null) {
      final entity = await _openOrNull(driveTx, data, inMemory);

      if (entity != null) {
        return DriveKeyAttempt.opened(key: inMemory, entity: entity);
      }
    }

    // Unlocked this session with "Remember on this device" off, or
    // forgotten: only the person opens it, so neither a stored key (there is
    // none) nor the sign-in password is tried.
    if (forgotten) {
      return const DriveKeyAttempt.failed(DriveUnlockFailure.notTried);
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
  /// in memory and, with [remember], under [profileKey] on its drive row (see
  /// [_keep]), and leaves the locked list.
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
    bool remember = true,
  }) async {
    final owner = await wallet.getAddress();

    // The user asked for this drive, which is what lets its wallet prompt
    // come back after being cancelled.
    _session.forgetWalletDeclined(ownerAddress: owner, driveId: driveId);

    // Forgotten drives are left out of "Try on my other locked drives": the
    // person unlocks a forgotten drive by itself, or it stays locked. Trying
    // the password on it here would sign for it and remember it again.
    final forgotten =
        tryOthers ? await _driveDao.forgottenDriveIds() : const <String>{};
    final others = [
      if (tryOthers)
        for (final drive in _session.currentLockedDrives)
          if (drive.ownerAddress == owner &&
              drive.driveId != driveId &&
              !forgotten.contains(drive.driveId))
            drive.driveId,
    ];

    // A Wander that can signs for this drive and every other locked one in
    // one approval, so trying the password on the others asks nothing more.
    // The user asked for all of them, so a prompt cancelled earlier doesn't
    // keep one out. Cancelling this one leaves them all locked.
    DriveMetadata? metadata;
    if (others.isNotEmpty &&
        wallet is ArConnectWallet &&
        wallet.canBatchSign &&
        !_session.batchSigningUnusable(owner)) {
      try {
        metadata = await _readLatest(driveId, owner);
      } catch (e) {
        logger.w('Could not read the metadata of $driveId: $e');
        return const DriveUnlockResult.failed(DriveUnlockFailure.unavailable);
      }

      if (metadata == null) {
        return const DriveUnlockResult.failed(DriveUnlockFailure.unavailable);
      }

      final lockedTypes = {
        for (final drive in _session.currentLockedDrives)
          drive.driveId: drive.signatureType,
      };
      final batch = await signInOneApproval(
        wallet: wallet,
        driveIds: [
          for (final (id, type) in [
            (driveId, _signatureTypeOf(metadata.tx)),
            for (final other in others)
              (other, lockedTypes[other] ?? DriveSignatureType.v1),
          ])
            if (await opensWithV2Signature(
                wallet: wallet, driveId: id, signatureType: type))
              id,
        ],
      );

      if (batch == DriveSignatureBatch.declined) {
        return const DriveUnlockResult.failed(
            DriveUnlockFailure.walletDeclined);
      }
    }

    final first = await _unlockOne(
      wallet: wallet,
      ownerAddress: owner,
      profileKey: profileKey,
      driveId: driveId,
      password: password,
      mayAskWallet: true,
      remember: remember,
      metadata: metadata,
    );

    if (!first.opened) {
      return DriveUnlockResult.failed(first.failure!);
    }

    final opened = [driveId];

    if (others.isNotEmpty) {
      // The drive asked for may prompt; the others share a small budget, so
      // one password tried on many drives can't become a prompt per drive.
      // After a batch their signatures are held, and they cost nothing.
      final budget = wallet is ArConnectWallet
          ? WalletPromptBudget(WalletPromptBudget.perPass)
          : null;

      for (final other in others) {
        final attempt = await _unlockOne(
          wallet: wallet,
          ownerAddress: owner,
          profileKey: profileKey,
          driveId: other,
          password: password,
          mayAskWallet: false,
          promptBudget: budget,
          remember: remember,
        );

        if (attempt.opened) {
          opened.add(other);
        }
      }
    }

    return DriveUnlockResult.opened(opened);
  }

  /// Whether [password] opens one of [ownerAddress]'s existing private
  /// drives: the check before a new private drive is made with a password
  /// the sign-in didn't prove. Null when it opens one, or why not.
  ///
  /// Locked drives first, oldest first: one that opens stays unlocked, kept
  /// as [unlock] keeps it. A wallet that prompts is asked at most
  /// [WalletPromptBudget.perPass] times. With no locked drive, the first of
  /// [knownPrivateDriveIds] is read and decrypted, and nothing is kept.
  Future<DriveUnlockFailure?> verifyDrivePassword({
    required Wallet wallet,
    required SecretKey? profileKey,
    required String password,
    List<String> knownPrivateDriveIds = const [],
  }) async {
    final owner = await wallet.getAddress();
    final budget = wallet is ArConnectWallet
        ? WalletPromptBudget(WalletPromptBudget.perPass)
        : null;
    // Oldest by creation first, as at sign-in: the drive most likely made
    // with the account's password.
    final createdAt = _arweave.cachedUserDriveCreationTimes(owner);
    DateTime created(LockedDrive drive) =>
        createdAt[drive.driveId] ?? drive.lastUpdated;
    // A drive this device was told not to keep a key for is not tried:
    // opening it here would store its key and undo "Forget on this device".
    final forgotten = await _driveDao.forgottenDriveIds();
    final locked = [
      for (final drive in _session.currentLockedDrives)
        if (drive.ownerAddress == owner && !forgotten.contains(drive.driveId))
          drive,
    ]..sort((a, b) => created(a).compareTo(created(b)));

    var unavailable = false;

    for (final drive in locked) {
      // Out of prompts: only drives whose signature is already held are
      // still tried.
      if (budget != null &&
          budget.remaining == 0 &&
          !_session.holdsSignatureFor(owner, drive.driveId)) {
        continue;
      }

      final attempt = await _unlockOne(
        wallet: wallet,
        ownerAddress: owner,
        profileKey: profileKey,
        driveId: drive.driveId,
        password: password,
        mayAskWallet: true,
        promptBudget: budget,
        remember: true,
      );

      switch (attempt.failure) {
        case null:
          return null;
        case DriveUnlockFailure.wrongPassword:
        case DriveUnlockFailure.notTried:
          continue;
        case DriveUnlockFailure.unavailable:
          unavailable = true;
          continue;
        case DriveUnlockFailure.walletDeclined:
        case DriveUnlockFailure.walletFailed:
          return attempt.failure;
      }
    }

    // Nothing to unlock with it: it is checked on one drive, and nothing is
    // kept. An open drive first; otherwise a drive this device was told to
    // forget, so it stays forgotten ([tryPassword] keeps no key).
    final forgottenLocked = [
      for (final drive in _session.currentLockedDrives)
        if (drive.ownerAddress == owner && forgotten.contains(drive.driveId))
          drive,
    ]..sort((a, b) => created(a).compareTo(created(b)));
    final checkOn = knownPrivateDriveIds.isNotEmpty
        ? knownPrivateDriveIds.first
        : forgottenLocked.firstOrNull?.driveId;

    if (locked.isEmpty && checkOn != null) {
      final driveId = checkOn;
      try {
        final driveTx = await _arweave.getLatestDriveTx(driveId, owner,
            maxRetries: unlockMaxRetries);
        if (driveTx == null) {
          return DriveUnlockFailure.unavailable;
        }
        final data = await _arweave.getEntityDataBytes(driveTx.id);
        final attempt = await tryPassword(
          wallet: wallet,
          driveTx: driveTx,
          data: data,
          password: password,
          promptBudget: budget,
        );
        return attempt.failure;
      } catch (e) {
        logger.w('Could not read $driveId to check a drive password: $e');
        return DriveUnlockFailure.unavailable;
      }
    }

    // Nothing to check it on yet (the drive list hasn't loaded): not a
    // verdict on the password.
    if (locked.isEmpty) return DriveUnlockFailure.unavailable;

    return unavailable
        ? DriveUnlockFailure.unavailable
        : DriveUnlockFailure.wrongPassword;
  }

  Future<DriveKeyAttempt> _unlockOne({
    required Wallet wallet,
    required String ownerAddress,
    required SecretKey? profileKey,
    required String driveId,
    required String password,
    required bool mayAskWallet,
    required bool remember,
    WalletPromptBudget? promptBudget,
    DriveMetadata? metadata,
  }) async {
    var drive = metadata;

    if (drive == null) {
      try {
        drive = await _readLatest(driveId, ownerAddress);
      } catch (e) {
        logger.w('Could not read the metadata of $driveId: $e');
      }

      if (drive == null) {
        return const DriveKeyAttempt.failed(DriveUnlockFailure.unavailable);
      }
    }

    final attempt = await tryPassword(
      wallet: wallet,
      driveTx: drive.tx,
      data: drive.data,
      password: password,
      mayAskWallet: mayAskWallet,
      promptBudget: promptBudget,
    );

    if (attempt.opened) {
      await _keep(attempt, profileKey, remember: remember);
    }

    return attempt;
  }

  /// [driveId]'s newest metadata, or null if it has none. Throws if it
  /// can't be read.
  Future<DriveMetadata?> _readLatest(
      String driveId, String ownerAddress) async {
    // A few quick tries, not the eight a sync makes: somebody is watching
    // the dialog, and "Couldn't reach the network" after a minute and a
    // half of backoff is a dialog that looks frozen.
    final driveTx = await _arweave.getLatestDriveTx(
      driveId,
      ownerAddress,
      maxRetries: unlockMaxRetries,
    );

    if (driveTx == null) return null;

    return (tx: driveTx, data: await _arweave.getEntityDataBytes(driveTx.id));
  }

  /// Keeps a proven key: in the memory vault and, with [remember] ("Remember
  /// on this device"), wrapped by the device key ([profileKey]) on the
  /// drive's row. Without it the key is kept for this session only and the
  /// next session starts with the drive locked.
  Future<void> _keep(
    DriveKeyAttempt attempt,
    SecretKey? profileKey, {
    required bool remember,
  }) async {
    final entity = attempt.entity!;
    final driveId = entity.id!;

    await _driveDao.putDriveKeyInMemory(
        driveID: driveId, driveKey: attempt.key!);

    if (remember) {
      await _driveDao.allowRememberingDriveKey(driveId);
    } else {
      await _driveDao.keepDriveKeyForSession(
          driveId: driveId, driveKey: attempt.key!);
    }

    await _driveDao.writeDriveEntity(
      name: entity.name!,
      entity: entity,
      driveKey: attempt.key,
      profileKey: profileKey,
    );

    _session.markUnlocked(driveId);
  }
}

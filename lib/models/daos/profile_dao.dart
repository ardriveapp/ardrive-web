import 'dart:convert';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/device_unlock/domain/device_key.dart';
import 'package:ardrive/device_unlock/domain/device_unlocker.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_logger/ardrive_logger.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

part 'profile_dao.g.dart';

class ProfilePasswordIncorrectException implements UntrackedException {}

/// A device key that does not open the profile: a wallet whose signature
/// changed, or a profile that was never unlocked that way.
class DeviceKeyMismatchException implements UntrackedException {
  const DeviceKeyMismatchException();
}

/// The profile is unlocked by something other than a password, or by a
/// method this build does not know.
class ProfileUnlockMethodException implements UntrackedException {
  const ProfileUnlockMethodException(this.method);

  final String? method;

  @override
  String toString() => 'ProfileUnlockMethodException($method)';
}

/// The profile was saved in a format this build does not know: by a newer
/// ArDrive, so this tab is running an older one. Reloading gets the newer
/// build. Nothing here may offer to sign out or forget the account: that
/// would delete a wallet this build simply can't read.
class ProfileFormatTooNewException implements UntrackedException {
  const ProfileFormatTooNewException(this.formatVersion);

  final int formatVersion;

  @override
  String toString() => 'ProfileFormatTooNewException($formatVersion)';
}

/// The profile was rewritten in the current format by another unlock while
/// this one was rewriting it.
class ProfileAlreadyMigratedException implements Exception {
  const ProfileAlreadyMigratedException();
}

/// The local profile format this build writes.
///
/// 1, before 3.0: the wallet and the public key encrypted with AES-GCM under
/// PBKDF2(password, keySalt), both with keySalt as the nonce. One nonce for
/// two messages under one key, and the public key is also stored in plain
/// text, so XOR gives the first bytes of the wallet's JSON, the private
/// exponent among them, without the password. Every copy of a format 1
/// profile must go: see [ProfileDao.needsOlderCopiesCleared].
///
/// 2: a random device salt and an unlock method. The device key is
/// HKDF(secret, deviceSalt, method) ([deriveDeviceKey]), where the secret is
/// PBKDF2(password, keySalt) for a password and a wallet signature
/// otherwise. Each kind of value has its own subkey ([deviceSubkey]): the
/// public key and the wallet are each sealed with a fresh random nonce
/// (`nonce || ciphertext || mac`), beside a key check, and drive keys on
/// drive rows are wrapped with the drive-key subkey, a fresh nonce and their
/// drive ID as AAD ([wrapDriveKey]).
///
/// Any other value is from a newer build: [ProfileFormatTooNewException].
const currentProfileFormat = 2;

@DriftAccessor(include: {'../queries/profile_queries.drift'})
class ProfileDao extends DatabaseAccessor<Database> with _$ProfileDaoMixin {
  ProfileDao(super.db);

  /// Loads the default profile with [password], the device password.
  ///
  /// A profile in the format before 3.0 is read with the code that wrote it
  /// and, once that has proven the password, rewritten in the current format
  /// ([migrateToCurrentFormat]). If the rewrite fails the profile is left as
  /// it was and still opens; it is tried again on the next unlock.
  ///
  /// The key returned, [ProfileLoadDetails.key], is what wraps drive keys on
  /// this device: the drive-key subkey in the current format, the password's
  /// key in the old one.
  ///
  /// Throws a [ProfilePasswordIncorrectException] if the password is wrong,
  /// and [ProfileFormatTooNewException] for a profile a newer build saved.
  Future<ProfileLoadDetails> loadDefaultProfile(String password) async {
    final profile = await defaultProfile().getSingle();

    switch (profile.formatVersion) {
      case 1:
        return _loadFormat1AndMigrate(profile, password);
      case currentProfileFormat:
        return _loadCurrentFormat(profile, password);
      default:
        throw ProfileFormatTooNewException(profile.formatVersion);
    }
  }

  Future<ProfileLoadDetails> _loadCurrentFormat(
    Profile profile,
    String password,
  ) async {
    final method = DeviceUnlockMethod.fromValue(profile.unlockMethod);
    if (method != DeviceUnlockMethod.password) {
      throw ProfileUnlockMethodException(profile.unlockMethod);
    }

    final passwordKey = await _passwordKey(password, profile.keySalt);
    final deviceKey = await deriveDeviceKey(
      secret: passwordKey,
      deviceSalt: profile.deviceSalt!,
      method: DeviceUnlockMethod.password,
    );

    return _openCurrentFormat(
      profile,
      deviceKey,
      onWrongKey: ProfilePasswordIncorrectException.new,
    );
  }

  /// Loads a current-format profile whose device key comes from a wallet
  /// ([DeviceUnlockMethod.wander], `solana` or `ethereum`): the key from
  /// `DeviceUnlocker`.
  ///
  /// Throws [DeviceKeyMismatchException] when [deviceKey] does not open it,
  /// as with a wallet whose signature changed: nothing is read with a wrong
  /// key.
  Future<ProfileLoadDetails> loadDefaultProfileWithDeviceKey(
    SecretKey deviceKey,
  ) async {
    final profile = await defaultProfile().getSingle();
    if (profile.formatVersion > currentProfileFormat) {
      throw ProfileFormatTooNewException(profile.formatVersion);
    }
    final keyCheck = profile.keyCheck;
    if (profile.formatVersion != currentProfileFormat ||
        keyCheck == null ||
        !await keyCheckMatches(deviceKey, keyCheck)) {
      throw const DeviceKeyMismatchException();
    }
    return _openCurrentFormat(
      profile,
      deviceKey,
      onWrongKey: DeviceKeyMismatchException.new,
    );
  }

  /// What a current-format profile keeps about its device key.
  Future<DeviceRecord?> deviceRecord() async {
    final profile = await getDefaultProfile();
    if (profile == null || profile.formatVersion != currentProfileFormat) {
      return null;
    }
    final method = DeviceUnlockMethod.fromValue(profile.unlockMethod);
    if (method == null || profile.deviceSalt == null) return null;
    return DeviceRecord(
      method: method,
      deviceSalt: profile.deviceSalt!,
      keyCheck: profile.keyCheck,
    );
  }

  Future<ProfileLoadDetails> _openCurrentFormat(
    Profile profile,
    SecretKey deviceKey, {
    required Exception Function() onWrongKey,
  }) async {
    final String publicKey;
    try {
      publicKey = utf8.decode(await openSealed(
        await deviceSubkey(deviceKey, DeviceKeyPurpose.publicKey),
        profile.encryptedPublicKey,
      ));
    } on SecretBoxAuthenticationError catch (_) {
      throw onWrongKey();
    }

    final driveKeyWrap =
        await deviceSubkey(deviceKey, DeviceKeyPurpose.driveKey);

    switch (ProfileType.values[profile.profileType]) {
      case ProfileType.json:
        final Map<String, dynamic> walletJwk;
        try {
          walletJwk = json.decode(utf8.decode(await openSealed(
            await deviceSubkey(deviceKey, DeviceKeyPurpose.wallet),
            profile.encryptedWallet,
          )));
        } on SecretBoxAuthenticationError catch (_) {
          throw onWrongKey();
        }
        return ProfileLoadDetails(
          details: profile,
          wallet: Wallet.fromJwk(walletJwk),
          key: driveKeyWrap,
          deviceKey: deviceKey,
          walletPublicKey: publicKey,
        );
      case ProfileType.arConnect:
        return ProfileLoadDetails(
          details: profile,
          // Knows its address from the key just unlocked, so unlocking never
          // asks Wander, which may be locked.
          wallet: ArConnectWallet(ArConnectService(), publicKey: publicKey),
          key: driveKeyWrap,
          deviceKey: deviceKey,
          walletPublicKey: publicKey,
        );
    }
  }

  /// The format before 3.0, read exactly as it was written, then rewritten.
  Future<ProfileLoadDetails> _loadFormat1AndMigrate(
    Profile profile,
    String password,
  ) async {
    final profileSalt = profile.keySalt;
    final profileKdRes =
        await compute<Map<String, dynamic>, ProfileKeyDerivationResult>(
            deriveKey, {
      'password': password,
      'salt': profileSalt,
    });

    // Checks the password for both JSON and ArConnect by decrypting the
    // stored public key.
    String publicKey;

    try {
      publicKey = await compute(decodeAndDecryptWithAeGsm, {
        'data': profile.encryptedPublicKey,
        'nonce': profileSalt,
        'key': profileKdRes.key,
      });
    } on SecretBoxAuthenticationError catch (_) {
      throw ProfilePasswordIncorrectException();
    }

    final parsedProfileType = ProfileType.values[profile.profileType];
    String? walletJson;
    final Wallet wallet;

    switch (parsedProfileType) {
      case ProfileType.json:
        try {
          walletJson = await compute(decodeAndDecryptWithAeGsm, {
            'data': profile.encryptedWallet,
            'nonce': profileSalt,
            'key': profileKdRes.key,
          });
        } on SecretBoxAuthenticationError catch (_) {
          throw ProfilePasswordIncorrectException();
        }
        wallet = Wallet.fromJwk(json.decode(walletJson!));
      case ProfileType.arConnect:
        wallet = ArConnectWallet(ArConnectService(), publicKey: publicKey);
    }

    try {
      final deviceKey = await migrateToCurrentFormat(
        profile: profile,
        format1Key: profileKdRes.key,
        publicKey: publicKey,
        walletJson: walletJson,
      );
      logger.i('The local profile was rewritten in format '
          '$currentProfileFormat');
      return ProfileLoadDetails(
        details: await defaultProfile().getSingle(),
        wallet: wallet,
        key: await deviceSubkey(deviceKey, DeviceKeyPurpose.driveKey),
        deviceKey: deviceKey,
        walletPublicKey: publicKey,
      );
    } catch (e) {
      // The transaction rolled back. Another unlock (another tab, a second
      // tap) may have rewritten the profile meanwhile: then it opens the
      // current way, with the same password.
      final now = await defaultProfile().getSingle();
      if (now.formatVersion == currentProfileFormat) {
        return _loadCurrentFormat(now, password);
      }
      // Otherwise the profile and every drive key are as they were, and the
      // profile still opens with the old format.
      logger.w('Could not rewrite the local profile in the current format; '
          'keeping the old one: ${e.runtimeType}');
    }

    return ProfileLoadDetails(
      details: await defaultProfile().getSingle(),
      wallet: wallet,
      key: profileKdRes.key,
      walletPublicKey: publicKey,
    );
  }

  /// Rewrites a format 1 profile in the current format, in one transaction,
  /// and returns its device key:
  ///
  /// - a new random device salt, and the device key from it and the
  ///   password's key ([format1Key], already proven);
  /// - the public key and the wallet sealed again under their subkeys, each
  ///   with its own random nonce, and a key check;
  /// - every drive key stored on this device unwrapped with the old key and
  ///   wrapped with the drive-key subkey and its drive ID.
  ///
  /// A stored drive key the old key can't open is useless anyway: it is
  /// dropped, and the drive marked so the next session starts with it locked
  /// (its password opens it again). It must not keep the account in format
  /// 1. Anything else that fails throws and rolls the whole of it back, as
  /// does a profile another unlock has rewritten meanwhile
  /// ([ProfileAlreadyMigratedException]).
  @visibleForTesting
  Future<SecretKey> migrateToCurrentFormat({
    required Profile profile,
    required SecretKey format1Key,
    required String publicKey,
    required String? walletJson,
  }) async {
    final deviceSalt = newDeviceSalt();
    final deviceKey = await deriveDeviceKey(
      secret: await format1Key.extractBytes(),
      deviceSalt: deviceSalt,
      method: DeviceUnlockMethod.password,
    );
    final driveKeyWrap =
        await deviceSubkey(deviceKey, DeviceKeyPurpose.driveKey);

    final sealedPublicKey = await seal(
      await deviceSubkey(deviceKey, DeviceKeyPurpose.publicKey),
      utf8.encode(publicKey),
    );
    final sealedWallet = walletJson == null
        ? Uint8List(0)
        : await seal(
            await deviceSubkey(deviceKey, DeviceKeyPurpose.wallet),
            utf8.encode(walletJson),
          );
    final keyCheck = await makeKeyCheck(deviceKey);

    await transaction(() async {
      final withKeys = await (select(attachedDatabase.drives)
            ..where((d) => d.encryptedKey.isNotNull()))
          .get();

      var dropped = 0;
      for (final drive in withKeys) {
        final List<int> driveKey;
        try {
          driveKey = await unwrapDriveKey(
            encryptedKey: drive.encryptedKey!,
            iv: drive.keyEncryptionIv!,
            wrapKey: format1Key,
            driveId: drive.id,
          );
        } on SecretBoxAuthenticationError {
          dropped++;
          await (update(attachedDatabase.drives)
                ..where((d) => d.id.equals(drive.id)))
              .write(const DrivesCompanion(
            encryptedKey: Value(null),
            keyEncryptionIv: Value(null),
          ));
          await into(attachedDatabase.forgottenDrives).insert(
            ForgottenDrivesCompanion.insert(driveId: drive.id),
            mode: InsertMode.insertOrIgnore,
          );
          continue;
        }
        final box = await wrapDriveKey(driveKey, driveKeyWrap, drive.id);
        await (update(attachedDatabase.drives)
              ..where((d) => d.id.equals(drive.id)))
            .write(DrivesCompanion(
          encryptedKey: Value(box.concatenation(nonce: false)),
          keyEncryptionIv: Value(Uint8List.fromList(box.nonce)),
        ));
      }
      if (dropped > 0) {
        logger.w('Dropped $dropped stored drive keys the profile key could '
            'not open; those drives start locked');
      }

      final updated = await (update(profiles)
            ..where((p) => p.id.equals(profile.id) & p.formatVersion.equals(1)))
          .write(ProfilesCompanion(
        formatVersion: const Value(currentProfileFormat),
        deviceSalt: Value(deviceSalt),
        unlockMethod: Value(DeviceUnlockMethod.password.value),
        encryptedPublicKey: Value(sealedPublicKey),
        encryptedWallet: Value(sealedWallet),
        keyCheck: Value(keyCheck),
        olderCopiesCleared: const Value(false),
      ));
      // Another unlock rewrote it first: this whole transaction, the drive
      // keys it rewrapped or dropped included, rolls back.
      if (updated != 1) {
        throw const ProfileAlreadyMigratedException();
      }
    });

    return deviceKey;
  }

  /// Whether this device may still hold format 1 copies of the profile to
  /// clear: older database stores, reset copies, free pages. True for a
  /// current-format profile until [markOlderCopiesCleared].
  Future<bool> needsOlderCopiesCleared() async {
    final profile = await getDefaultProfile();
    return profile != null &&
        profile.formatVersion == currentProfileFormat &&
        !profile.olderCopiesCleared;
  }

  Future<void> markOlderCopiesCleared() =>
      update(profiles).write(const ProfilesCompanion(
        olderCopiesCleared: Value(true),
      ));

  Future<List<int>> _passwordKey(String password, List<int> keySalt) async {
    final derived =
        await compute<Map<String, dynamic>, ProfileKeyDerivationResult>(
            deriveKey, {
      'password': password,
      'salt': keySalt,
    });
    return derived.key.extractBytes();
  }

  Future<Profile?> getDefaultProfile() async {
    final profile = await (select(profiles)..limit(1)).getSingleOrNull();
    return profile;
  }

  Future<void> deleteProfile() async {
    final profile = await defaultProfile().getSingle();

    await (delete(profiles)..where((p) => p.id.equals(profile.id))).go();
  }

  /// Adds a profile for [wallet], in the current format, unlocked on this
  /// device by [password]. Returns the key that wraps the drive keys this
  /// device remembers (the drive-key subkey of the device key).
  Future<SecretKey> addProfile(
    String username,
    String password,
    Wallet wallet,
    ProfileType profileType, {
    String? sourceWalletAddress,
  }) async {
    logger.d('Adding profile with type $profileType');

    final keySalt = randomBytes(16);
    final deviceSalt = newDeviceSalt();
    final deviceKey = await deriveDeviceKey(
      secret: await _passwordKey(password, keySalt),
      deviceSalt: deviceSalt,
      method: DeviceUnlockMethod.password,
    );

    await _insertProfile(
      username: username,
      wallet: wallet,
      profileType: profileType,
      keySalt: keySalt,
      record: DeviceRecord(
        method: DeviceUnlockMethod.password,
        deviceSalt: deviceSalt,
        keyCheck: await makeKeyCheck(deviceKey),
      ),
      deviceKey: deviceKey,
      sourceWalletAddress: sourceWalletAddress,
    );

    return deviceSubkey(deviceKey, DeviceKeyPurpose.driveKey);
  }

  /// Adds a profile whose device key comes from a wallet: [record] holds the
  /// method, device salt and key check that `DeviceUnlocker` made with
  /// [deviceKey]. For signing in without a password.
  Future<void> addProfileWithDeviceKey({
    required Wallet wallet,
    required ProfileType profileType,
    required DeviceRecord record,
    required SecretKey deviceKey,
    String? sourceWalletAddress,
  }) {
    assert(record.method != DeviceUnlockMethod.password);
    return _insertProfile(
      username: 'user.username',
      wallet: wallet,
      profileType: profileType,
      // No password, so no password salt. The column is not null.
      keySalt: Uint8List(0),
      record: record,
      deviceKey: deviceKey,
      sourceWalletAddress: sourceWalletAddress,
    );
  }

  Future<void> _insertProfile({
    required String username,
    required Wallet wallet,
    required ProfileType profileType,
    required Uint8List keySalt,
    required DeviceRecord record,
    required SecretKey deviceKey,
    String? sourceWalletAddress,
  }) async {
    final publicKey = await wallet.getOwner();
    final encryptedWallet = switch (profileType) {
      ProfileType.json => await seal(
          await deviceSubkey(deviceKey, DeviceKeyPurpose.wallet),
          utf8.encode(json.encode(wallet.toJwk())),
        ),
      // Wander keeps the key; the profile holds no wallet.
      ProfileType.arConnect => Uint8List(0),
    };

    await into(profiles).insert(
      ProfilesCompanion.insert(
        id: await wallet.getAddress(),
        username: username,
        encryptedWallet: encryptedWallet,
        keySalt: keySalt,
        profileType: profileType.index,
        walletPublicKey: publicKey,
        encryptedPublicKey: await seal(
          await deviceSubkey(deviceKey, DeviceKeyPurpose.publicKey),
          utf8.encode(publicKey),
        ),
        sourceWalletAddress: Value(sourceWalletAddress),
        formatVersion: const Value(currentProfileFormat),
        deviceSalt: Value(record.deviceSalt),
        unlockMethod: Value(record.method.value),
        keyCheck: Value(record.keyCheck),
      ),
    );
  }
}

class ProfileLoadDetails {
  final Profile details;
  final Wallet wallet;

  /// What wraps drive keys on this device: the drive-key subkey of the device
  /// key, or for a format 1 profile that could not be rewritten, the
  /// password's key.
  final SecretKey key;

  /// The device key itself, for a current-format profile.
  final SecretKey? deviceKey;
  final String walletPublicKey;
  ProfileLoadDetails({
    required this.details,
    required this.wallet,
    required this.key,
    required this.walletPublicKey,
    this.deviceKey,
  });
}

Future<String> decodeAndDecryptWithAeGsm(
  Map<String, dynamic> args,
) async {
  ArDriveCrypto crypto = ArDriveCrypto();

  return utf8.decode(
    await aesGcm.decrypt(
      crypto.secretBoxFromDataWithMacConcatenation(
        args['data'] as Uint8List,
        nonce: args['nonce'] as Uint8List,
      ),
      secretKey: args['key'] as SecretKey,
    ),
  );
}

Future<ProfileKeyDerivationResult> deriveKey(
  Map<String, dynamic> args,
) {
  ArDriveCrypto crypto = ArDriveCrypto();

  return crypto.deriveProfileKey(
      args['password'] as String, args['salt'] as List<int>?);
}

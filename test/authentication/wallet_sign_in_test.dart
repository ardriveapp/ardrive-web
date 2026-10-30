import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/device_unlock/data/device_tabs.dart';
import 'package:ardrive/device_unlock/domain/device_key.dart';
import 'package:ardrive/device_unlock/domain/device_secret_source.dart';
import 'package:ardrive/device_unlock/domain/device_unlocker.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/locked_drives/data/sign_in_password_proof_store.dart';
import 'package:ardrive/locked_drives/domain/drive_unlock_session.dart';
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:ardrive/models/database/database_helpers.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/user/repositories/user_repository.dart';
import 'package:ardrive/utils/metadata_cache.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stash_memory/stash_memory.dart';

import '../test_utils/locked_drive_fixtures.dart' show MemoryKeyValueStore;
import '../test_utils/utils.dart';

class _MockArioSDK extends Mock implements ArioSDK {}

class _MockDeviceTabs extends Mock implements DeviceTabs {}

/// A wallet that always gives the same signature, as an ordinary account
/// does.
DeviceSecretSource _wallet(DeviceUnlockMethod method, [int seed = 7]) =>
    DeviceSecretSource.fromSecret(
        method, Uint8List.fromList(List.filled(64, seed)));

/// A wallet whose prompt is refused, counting how often it is asked.
class _Refusing implements DeviceSecretSource {
  var asked = 0;

  @override
  DeviceUnlockMethod get method => DeviceUnlockMethod.wander;

  @override
  Future<Uint8List> secret(Uint8List deviceSalt) async {
    asked++;
    throw const DeviceUnlockDeclined();
  }
}

/// Signing in with a browser wallet and no password (the 3.0 password
/// design, P3), over a real profile store.
void main() {
  late Database db;
  late ArDriveAuthImpl auth;
  late MockArweaveService arweave;
  late DriveUnlockSession session;
  late DeviceUnlocker deviceUnlocker;
  final wallet = getTestWallet();
  late String address;

  setUpAll(() async {
    address = await wallet.getAddress();
  });

  setUp(() async {
    db = getTestDb();
    arweave = MockArweaveService();
    when(() => arweave.getWalletBalance(any()))
        .thenAnswer((_) async => BigInt.zero);
    when(() => arweave.getPendingTxFees(any()))
        .thenAnswer((_) async => BigInt.zero);
    session = DriveUnlockSession();
    deviceUnlocker = DeviceUnlocker();
    final biometrics = MockBiometricAuthentication();
    when(() => biometrics.isEnabled()).thenAnswer((_) async => false);
    final tabs = _MockDeviceTabs();

    auth = ArDriveAuthImpl(
      arweave: arweave,
      userRepository: UserRepository(db.profileDao, arweave, _MockArioSDK()),
      crypto: ArDriveCrypto(),
      biometricAuthentication: biometrics,
      secureKeyValueStore: MockSecureKeyValueStore(),
      arConnectService: MockArConnectService(),
      databaseHelpers: DatabaseHelpers(db),
      metadataCache:
          await MetadataCache.fromCacheStore(await newMemoryCacheStore()),
      driveUnlocker: DriveUnlocker(
        crypto: ArDriveCrypto(),
        arweave: arweave,
        driveDao: db.driveDao,
        session: session,
      ),
      deviceTabs: tabs,
      signInPasswordProofStore:
          SignInPasswordProofStore(store: () async => MemoryKeyValueStore()),
      deviceUnlocker: deviceUnlocker,
    );
  });

  tearDown(() => db.close());

  Future<Profile> profile() => db.profileDao.defaultProfile().getSingle();

  group('loginWithWallet', () {
    for (final (method, type) in [
      (DeviceUnlockMethod.wander, ProfileType.arConnect),
      (DeviceUnlockMethod.solana, ProfileType.json),
      (DeviceUnlockMethod.ethereum, ProfileType.json),
    ]) {
      test(
          '${method.value}: saves a profile its wallet opens, with no '
          'password and no drive tried', () async {
        final user = await auth.loginWithWallet(wallet, type, _wallet(method),
            sourceWalletAddress:
                method == DeviceUnlockMethod.wander ? null : 'source');

        expect(user.walletAddress, address);
        expect(user.password, isEmpty);
        final saved = await profile();
        expect(saved.unlockMethod, method.value);
        expect(saved.keyCheck, isNotNull);
        expect(saved.keySalt, isEmpty, reason: 'no password, so no salt');
        // No drive check: a browser wallet's sign-in reads no drive.
        verifyNever(() => arweave.getUniqueUserDriveEntityTxs(any(),
            maxRetries: any(named: 'maxRetries')));
        expect(session.signInPasswordProven(address), isNull);
      });
    }

    test('a refused approval saves nothing', () async {
      final refusing = _Refusing();

      await expectLater(
        auth.loginWithWallet(wallet, ProfileType.arConnect, refusing),
        throwsA(isA<DeviceUnlockRefusedException>()
            .having((e) => e.status, 'status', DeviceUnlockStatus.declined)),
      );
      expect(await db.profileDao.getDefaultProfile(), isNull);
      expect(refusing.asked, 1);
    });

    test('asks again on the next try after a refusal', () async {
      final refusing = _Refusing();
      await expectLater(
          auth.loginWithWallet(wallet, ProfileType.arConnect, refusing),
          throwsA(isA<DeviceUnlockRefusedException>()));

      await auth.loginWithWallet(
          wallet, ProfileType.arConnect, _wallet(DeviceUnlockMethod.wander));

      expect(await db.profileDao.getDefaultProfile(), isNotNull);
    });

    test(
        'replacing this account\'s profile from before 3.0 drops the drive '
        'keys its password wrapped, and those drives', () async {
      // As P2 saved it: under the old sign-in password.
      await db.profileDao.addProfile(
          'user.username', 'old password', wallet, ProfileType.arConnect);
      await db.into(db.drives).insert(DrivesCompanion.insert(
            id: 'remembered',
            rootFolderId: 'root',
            ownerAddress: address,
            name: 'Remembered',
            privacy: 'private',
            encryptedKey: Value(Uint8List(48)),
            keyEncryptionIv: Value(Uint8List(12)),
          ));
      await db.into(db.drives).insert(DrivesCompanion.insert(
            id: 'public',
            rootFolderId: 'root2',
            ownerAddress: address,
            name: 'Public',
            privacy: 'public',
          ));

      await auth.loginWithWallet(
          wallet, ProfileType.arConnect, _wallet(DeviceUnlockMethod.wander));

      expect((await profile()).unlockMethod, DeviceUnlockMethod.wander.value);
      final ids = (await db.select(db.drives).get()).map((d) => d.id);
      expect(ids, ['public']);
    });

    test(
        'an existing MetaMask account\'s typed password is tried on its '
        'drives and kept for the session only', () async {
      when(() => arweave.getUniqueUserDriveEntityTxs(any(),
          maxRetries: any(named: 'maxRetries'))).thenAnswer((_) async => []);

      final user = await auth.loginWithWallet(
        wallet,
        ProfileType.json,
        _wallet(DeviceUnlockMethod.ethereum),
        sourceWalletAddress: '0xabc',
        password: 'their password',
      );

      expect(user.password, 'their password');
      verify(() => arweave.getUniqueUserDriveEntityTxs(any(),
          maxRetries: any(named: 'maxRetries'))).called(1);
      expect(session.signInPasswordProven(address), isTrue);
      expect((await profile()).keySalt, isEmpty,
          reason: 'the profile is the wallet\'s, not the password\'s');
    });
  });

  group('unlockWithWallet', () {
    test('the same wallet opens the account and its drive key wrap', () async {
      final first = await auth.loginWithWallet(
          wallet, ProfileType.json, _wallet(DeviceUnlockMethod.solana),
          sourceWalletAddress: 'sol');
      await auth.logoutForTest();

      final user =
          await auth.unlockWithWallet(_wallet(DeviceUnlockMethod.solana));

      expect(user.walletAddress, address);
      expect(user.password, isEmpty);
      expect(await user.cipherKey.extractBytes(),
          await first.cipherKey.extractBytes());
      expect(user.wallet.toJwk(), wallet.toJwk(),
          reason: 'the derived wallet comes back without being made again');
    });

    test('a wallet that signs differently opens nothing', () async {
      await auth.loginWithWallet(
          wallet, ProfileType.json, _wallet(DeviceUnlockMethod.ethereum),
          sourceWalletAddress: '0xabc');
      await auth.logoutForTest();

      await expectLater(
        auth.unlockWithWallet(_wallet(DeviceUnlockMethod.ethereum, 9)),
        throwsA(isA<DeviceUnlockRefusedException>()
            .having((e) => e.status, 'status', DeviceUnlockStatus.mismatch)),
      );
    });

    test('a refusal opens nothing, and Continue asks again', () async {
      await auth.loginWithWallet(
          wallet, ProfileType.arConnect, _wallet(DeviceUnlockMethod.wander));
      await auth.logoutForTest();
      final refusing = _Refusing();

      await expectLater(auth.unlockWithWallet(refusing),
          throwsA(isA<DeviceUnlockRefusedException>()));
      await expectLater(auth.unlockWithWallet(refusing),
          throwsA(isA<DeviceUnlockRefusedException>()));

      expect(refusing.asked, 2);
      final user =
          await auth.unlockWithWallet(_wallet(DeviceUnlockMethod.wander));
      expect(user.walletAddress, address);
    });

    test('another wallet type is refused before anything is asked', () async {
      await auth.loginWithWallet(
          wallet, ProfileType.arConnect, _wallet(DeviceUnlockMethod.wander));
      await auth.logoutForTest();

      await expectLater(
          auth.unlockWithWallet(_wallet(DeviceUnlockMethod.ethereum)),
          throwsA(isA<DeviceUnlockRefusedException>()));
    });
  });

  group('savedAccount', () {
    test('a password account has no wallet method', () async {
      await db.profileDao
          .addProfile('user.username', 'pw', wallet, ProfileType.json);

      final account = await auth.savedAccount();

      expect(account!.walletMethod, isNull);
      expect(account.isLegacyWalletProfile, isFalse);
    });

    test('a Wander or Solana profile from before 3.0 opens with its wallet',
        () async {
      await db.profileDao
          .addProfile('user.username', 'pw', wallet, ProfileType.arConnect);
      var account = await auth.savedAccount();
      expect(account!.walletMethod, DeviceUnlockMethod.wander);
      expect(account.isLegacyWalletProfile, isTrue);

      await db.profileDao.deleteProfile();
      await db.profileDao.addProfile(
          'user.username', 'pw', wallet, ProfileType.json,
          sourceWalletAddress: 'So1anaAddress');
      account = await auth.savedAccount();
      expect(account!.walletMethod, DeviceUnlockMethod.solana);
      expect(account.isLegacyWalletProfile, isTrue);
    });

    test('a MetaMask profile from before 3.0 keeps its password', () async {
      await db.profileDao.addProfile(
          'user.username', 'pw', wallet, ProfileType.json,
          sourceWalletAddress: '0xabc');

      final account = await auth.savedAccount();

      expect(account!.walletMethod, isNull,
          reason: 'its password picks its wallet');
    });

    test('a profile a wallet saved opens with that wallet', () async {
      await auth.loginWithWallet(
          wallet, ProfileType.json, _wallet(DeviceUnlockMethod.ethereum),
          sourceWalletAddress: '0xabc');

      final account = await auth.savedAccount();

      expect(account!.walletMethod, DeviceUnlockMethod.ethereum);
      expect(account.isLegacyWalletProfile, isFalse);
    });
  });
}

extension on ArDriveAuthImpl {
  /// A reload: the session is gone and the profile stays.
  Future<void> logoutForTest() async => currentUser = null;
}

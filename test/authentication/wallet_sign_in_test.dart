import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/arns/data/arns_pending_action_store.dart';
import 'package:ardrive/arns/data/arns_wallet_store.dart';
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
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/graphql_retry.dart' show GraphQLException;
import 'package:ardrive/utils/metadata_cache.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:arweave/arweave.dart' show Wallet;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stash_memory/stash_memory.dart';

import '../test_utils/locked_drive_fixtures.dart'
    show MemoryKeyValueStore, makeWebPrivateDrive;
import '../test_utils/utils.dart';

class _MockArioSDK extends Mock implements ArioSDK {}

class _MockDeviceTabs extends Mock implements DeviceTabs {}

class _CountingWipe extends DatabaseHelpers {
  _CountingWipe(super.db);
  var wipes = 0;

  @override
  Future<List<String>> wipeAfterSignOut() async {
    wipes++;
    return const [];
  }
}

class _FailingHelpers extends DatabaseHelpers {
  _FailingHelpers(super.db);

  @override
  Future<void> deleteAllTables({bool rethrowOnError = false}) async {
    if (rethrowOnError) throw StateError('disk full');
  }
}

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
  late _MockDeviceTabs tabs;
  late MockSecureKeyValueStore secure;
  late MemoryKeyValueStore arnsKv;
  late DatabaseHelpers helpers;
  late SignInPasswordProofStore proofs;
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
    tabs = _MockDeviceTabs();
    secure = MockSecureKeyValueStore();
    when(() => secure.remove(any())).thenAnswer((_) async => true);
    arnsKv = MemoryKeyValueStore();
    helpers = DatabaseHelpers(db);
    proofs = SignInPasswordProofStore(store: () async => MemoryKeyValueStore());

    auth = ArDriveAuthImpl(
      arweave: arweave,
      userRepository: UserRepository(db.profileDao, arweave, _MockArioSDK()),
      crypto: ArDriveCrypto(),
      biometricAuthentication: biometrics,
      secureKeyValueStore: secure,
      arnsWalletStore: ArNSWalletStore(openStore: () async => arnsKv),
      arnsPendingActionStore:
          ArNSPendingActionStore(openStore: () async => arnsKv),
      arConnectService: MockArConnectService(),
      databaseHelpers: helpers,
      metadataCache:
          await MetadataCache.fromCacheStore(await newMemoryCacheStore()),
      driveUnlocker: DriveUnlocker(
        crypto: ArDriveCrypto(),
        arweave: arweave,
        driveDao: db.driveDao,
        session: session,
      ),
      deviceTabs: tabs,
      signInPasswordProofStore: proofs,
      deviceUnlocker: deviceUnlocker,
    );
  });

  Future<ArDriveAuthImpl> authWith(DatabaseHelpers helpers) async =>
      ArDriveAuthImpl(
        arweave: arweave,
        userRepository: UserRepository(db.profileDao, arweave, _MockArioSDK()),
        crypto: ArDriveCrypto(),
        biometricAuthentication: MockBiometricAuthentication(),
        secureKeyValueStore: secure,
        arConnectService: MockArConnectService(),
        databaseHelpers: helpers,
        deviceTabs: tabs,
        deviceUnlocker: DeviceUnlocker(),
        signInPasswordProofStore: proofs,
        metadataCache:
            await MetadataCache.fromCacheStore(await newMemoryCacheStore()),
      );

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

    test('H1: a saved keyfile account is never what a Solana sign-in opens',
        () async {
      final other = await Wallet.generate();
      final otherAddress = await other.getAddress();
      await db.profileDao
          .addProfile('user.username', 'pw', other, ProfileType.json);

      final user = await auth.loginWithWallet(
          wallet, ProfileType.json, _wallet(DeviceUnlockMethod.solana),
          sourceWalletAddress: 'solana-source');

      expect(user.walletAddress, address);
      expect(user.walletAddress, isNot(otherAddress));
      expect(user.sourceWalletAddress, 'solana-source');
      final rows = await db.select(db.profiles).get();
      expect(rows.map((r) => r.id), [address]);
      expect(auth.currentUser.walletAddress, address);
    });

    Future<Wallet> savePreviousAccount() async {
      final other = await Wallet.generate();
      final otherAddress = await other.getAddress();
      await db.profileDao
          .addProfile('user.username', 'pw', other, ProfileType.json);
      await db.into(db.drives).insert(DrivesCompanion.insert(
            id: 'theirs',
            rootFolderId: 'r',
            ownerAddress: otherAddress,
            name: 'Theirs',
            privacy: 'public',
          ));
      await ArNSWalletStore(openStore: () async => arnsKv)
          .link(otherAddress, const LinkedArNSWallet(address: 'sol-names'));
      return other;
    }

    test('switching account does what a sign-out does', () async {
      final other = await savePreviousAccount();
      final otherAddress = await other.getAddress();
      when(() => tabs.announceSignedOut()).thenReturn(null);
      final signedOut = <User?>[];
      auth.onAuthStateChanged().listen(signedOut.add);
      await proofs.markUnproven(otherAddress);

      await auth.loginWithWallet(
          wallet, ProfileType.json, _wallet(DeviceUnlockMethod.solana),
          sourceWalletAddress: 'solana-source');
      await Future<void>.delayed(Duration.zero);

      expect(
          await ArNSWalletStore(openStore: () async => arnsKv)
              .linked(otherAddress),
          isNull);
      expect(await proofs.isUnproven(otherAddress), isFalse);
      expect(signedOut.first, isNull,
          reason: 'preferences clear on the signed-out event');
      verify(() => secure.remove('password')).called(1);
      verify(() => secure.remove('biometricEnabled')).called(1);
      verify(() => tabs.announceSignedOut()).called(1);
    });

    test('a failed wipe aborts the switch and saves nothing', () async {
      final other = await savePreviousAccount();
      final failing = _FailingHelpers(db);
      final broken = await authWith(failing);

      await expectLater(
          broken.loginWithWallet(
              wallet, ProfileType.json, _wallet(DeviceUnlockMethod.solana)),
          throwsA(isA<AuthenticationUnknownException>()));

      final ids = (await db.select(db.profiles).get()).map((p) => p.id);
      expect(ids, isNot(contains(address)));
      expect(ids.length <= 1, isTrue);
      expect(other, isNotNull);
    });

    test(
        'a password sign-in keeps the session state it just made for the '
        'new account', () async {
      await savePreviousAccount();
      when(() => tabs.announceSignedOut()).thenReturn(null);
      when(() => arweave.getUniqueUserDriveEntityTxs(any(),
          maxRetries: any(named: 'maxRetries'))).thenAnswer((_) async => []);

      await auth.loginWithWallet(
        wallet,
        ProfileType.json,
        _wallet(DeviceUnlockMethod.ethereum),
        sourceWalletAddress: '0xabc',
        password: 'their password',
      );

      expect(session.signInPasswordProven(address), isTrue);
    });

    Future<void> expectPreviousAccountKept(Wallet other) async {
      final ids = (await db.select(db.profiles).get()).map((p) => p.id);
      expect(ids, [await other.getAddress()]);
      expect((await db.select(db.drives).get()).map((d) => d.id), ['theirs']);
    }

    test('a declined wallet prompt keeps the previous account', () async {
      final other = await savePreviousAccount();

      await expectLater(
          auth.loginWithWallet(wallet, ProfileType.arConnect, _Refusing()),
          throwsA(isA<DeviceUnlockRefusedException>()));

      await expectPreviousAccountKept(other);
      verifyNever(() => tabs.announceSignedOut());
    });

    test('a wrong MetaMask password keeps the previous account', () async {
      final other = await savePreviousAccount();
      final drive = await makeWebPrivateDrive(
          wallet: wallet,
          driveId: '6939b9e0-cc98-42cb-bae0-5888eca78885',
          password: 'right');
      when(() => arweave.cachedUserDriveCreationTimes(any())).thenReturn({});
      when(() => arweave.getUniqueUserDriveEntityTxs(any(),
              maxRetries: any(named: 'maxRetries')))
          .thenAnswer((_) async => [drive.tx]);
      when(() => arweave.getEntityDataBytes(drive.tx.id,
              configuredGatewayOnly: any(named: 'configuredGatewayOnly')))
          .thenAnswer((_) async => drive.data);

      await expectLater(
          auth.loginWithWallet(
              wallet, ProfileType.json, _wallet(DeviceUnlockMethod.ethereum),
              sourceWalletAddress: '0xabc', password: 'typo'),
          throwsA(isA<PasswordOpensNoDriveException>()));

      await expectPreviousAccountKept(other);
      verifyNever(() => tabs.announceSignedOut());
    });

    test('a gateway failure keeps the previous account', () async {
      final other = await savePreviousAccount();
      when(() => arweave.getUniqueUserDriveEntityTxs(any(),
              maxRetries: any(named: 'maxRetries')))
          .thenThrow(GraphQLException('down'));

      await expectLater(
          auth.loginWithWallet(
              wallet, ProfileType.json, _wallet(DeviceUnlockMethod.ethereum),
              sourceWalletAddress: '0xabc', password: 'pw'),
          throwsA(isA<AuthenticationGatewayException>()));

      await expectPreviousAccountKept(other);
    });

    test('a switch runs the post-sign-out wipe', () async {
      await savePreviousAccount();
      when(() => tabs.announceSignedOut()).thenReturn(null);
      final wiped = _CountingWipe(db);
      final counted = await authWith(wiped);

      await counted.loginWithWallet(
          wallet, ProfileType.json, _wallet(DeviceUnlockMethod.solana));

      expect(wiped.wipes, 1);
    });

    test('a same-address MetaMask sign-in keeps its drives', () async {
      await db.profileDao
          .addProfile('user.username', 'pw', wallet, ProfileType.json);
      await db.into(db.drives).insert(DrivesCompanion.insert(
            id: 'mine',
            rootFolderId: 'r',
            ownerAddress: address,
            name: 'Mine',
            privacy: 'public',
          ));
      when(() => arweave.getUniqueUserDriveEntityTxs(any(),
          maxRetries: any(named: 'maxRetries'))).thenAnswer((_) async => []);

      await auth.loginWithWallet(
          wallet, ProfileType.json, _wallet(DeviceUnlockMethod.ethereum),
          sourceWalletAddress: '0xabc', password: 'pw');

      expect((await db.select(db.drives).get()).map((d) => d.id), ['mine']);
    });

    test('the same account keeps its drives', () async {
      await db.profileDao
          .addProfile('user.username', 'pw', wallet, ProfileType.json);
      await db.into(db.drives).insert(DrivesCompanion.insert(
            id: 'mine',
            rootFolderId: 'r',
            ownerAddress: address,
            name: 'Mine',
            privacy: 'public',
          ));

      await auth.loginWithWallet(
          wallet, ProfileType.json, _wallet(DeviceUnlockMethod.solana));

      expect((await db.select(db.drives).get()).map((d) => d.id), ['mine']);
      verifyNever(() => tabs.announceSignedOut());
    });

    test('H4: the account it replaces leaves no drives behind', () async {
      final other = await Wallet.generate();
      final otherAddress = await other.getAddress();
      await db.profileDao
          .addProfile('user.username', 'pw', other, ProfileType.json);
      await db.into(db.drives).insert(DrivesCompanion.insert(
            id: 'theirs',
            rootFolderId: 'r',
            ownerAddress: otherAddress,
            name: 'Theirs',
            privacy: 'public',
          ));

      await auth.loginWithWallet(
          wallet, ProfileType.json, _wallet(DeviceUnlockMethod.solana),
          sourceWalletAddress: 'solana-source');

      expect(await db.select(db.drives).get(), isEmpty);
    });

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
        'a drive someone else owns, opened here by its share link, goes too, '
        'rows and all: its link opens it again, and a row kept without its '
        'key would only be skipped by every sync', () async {
      await db.profileDao.addProfile(
          'user.username', 'old password', wallet, ProfileType.arConnect);
      await db.into(db.drives).insert(DrivesCompanion.insert(
            id: 'shared',
            rootFolderId: 'rootX',
            ownerAddress: 'someone-else',
            name: 'Shared with me',
            privacy: 'private',
            encryptedKey: Value(Uint8List(48)),
            keyEncryptionIv: Value(Uint8List(12)),
          ));
      await db.into(db.drives).insert(DrivesCompanion.insert(
            id: 'own',
            rootFolderId: 'root',
            ownerAddress: address,
            name: 'Mine',
            privacy: 'private',
            encryptedKey: Value(Uint8List(48)),
            keyEncryptionIv: Value(Uint8List(12)),
          ));

      await auth.loginWithWallet(
          wallet, ProfileType.arConnect, _wallet(DeviceUnlockMethod.wander));

      expect(await db.select(db.drives).get(), isEmpty);
    });

    test(
        'a refusal on a profile from before 3.0 keeps the profile and the '
        'drive keys it remembered', () async {
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

      await expectLater(
          auth.loginWithWallet(wallet, ProfileType.arConnect, _Refusing()),
          throwsA(isA<DeviceUnlockRefusedException>()));

      expect((await profile()).unlockMethod, DeviceUnlockMethod.password.value);
      final rows = await db.select(db.drives).get();
      expect(rows.single.encryptedKey, isNotNull);
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

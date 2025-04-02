import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/daos/profile_dao.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/metadata_cache.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stash_memory/stash_memory.dart';

import '../test_utils/utils.dart';

class TransactionCommonMixinFake extends Fake
    implements TransactionCommonMixin {
  final Map<String, String> _tags = {};

  void setTag(String name, String value) {
    _tags[name] = value;
  }

  @override
  List<TransactionCommonMixin$Tag> get tags => _tags.entries
      .map((e) => TransactionCommonMixin$Tag()
        ..name = e.key
        ..value = e.value)
      .toList();
}

final fakePrivateDriveV1 = TransactionCommonMixinFake()
  ..setTag(EntityTag.drivePrivacy, DrivePrivacyTag.private)
  ..setTag(EntityTag.driveId, 'some_drive_id')
  ..setTag(EntityTag.signatureType, '1');

void main() {
  late ArDriveAuthImpl arDriveAuth;
  late MockArweaveService mockArweaveService;
  late MockUserRepository mockUserRepository;
  late MockArDriveCrypto mockArDriveCrypto;
  late MockBiometricAuthentication mockBiometricAuthentication;
  late MockSecureKeyValueStore mockSecureKeyValueStore;
  late MockArConnectService mockArConnectService;
  late MockDatabaseHelpers mockDatabaseHelpers;

  final wallet = getTestWallet();

  setUp(() async {
    mockArweaveService = MockArweaveService();
    mockUserRepository = MockUserRepository();
    mockArDriveCrypto = MockArDriveCrypto();
    mockBiometricAuthentication = MockBiometricAuthentication();
    mockSecureKeyValueStore = MockSecureKeyValueStore();
    mockArConnectService = MockArConnectService();
    mockDatabaseHelpers = MockDatabaseHelpers();

    final metadataCache = await MetadataCache.fromCacheStore(
      await newMemoryCacheStore(),
    );

    arDriveAuth = ArDriveAuthImpl(
      arweave: mockArweaveService,
      userRepository: mockUserRepository,
      crypto: mockArDriveCrypto,
      databaseHelpers: mockDatabaseHelpers,
      arConnectService: mockArConnectService,
      biometricAuthentication: mockBiometricAuthentication,
      secureKeyValueStore: mockSecureKeyValueStore,
      metadataCache: metadataCache,
    );

    registerFallbackValue(DriveEntity(
      id: 'some_id',
      rootFolderId: 'some_id',
    ));

    when(() => mockArConnectService.checkPermissions()).thenAnswer(
      (invocation) => Future.value(true),
    );
    when(() => mockArConnectService.isExtensionPresent()).thenAnswer(
      (invocation) => true,
    );
    when(() => mockArConnectService.disconnect()).thenAnswer(
      (invocation) => Future.value(null),
    );
  });

  group('ArDriveAuth', () {
    group('isUserLoggedIn method', () {
      test('Should return true when user is logged in', () async {
        when(() => mockUserRepository.hasUser()).thenAnswer((_) async => true);
        final isLoggedIn = await arDriveAuth.isUserLoggedIn();

        expect(isLoggedIn, true);
      });

      test('Should return false when user is not logged in', () async {
        when(() => mockUserRepository.hasUser()).thenAnswer((_) async => false);
        final isLoggedIn = await arDriveAuth.isUserLoggedIn();

        expect(isLoggedIn, false);
      });
    });

    group('isExistingUser method', () {
      test('Should return true when user is existing', () async {
        when(() => mockArweaveService.getUniqueUserDriveEntityTxs(any(),
                maxRetries: any(named: 'maxRetries')))
            .thenAnswer((_) async => [fakePrivateDriveV1]);
        final isExisting = await arDriveAuth.isExistingUser(wallet);

        expect(isExisting, true);
      });

      test('Should return false when user is not existing', () async {
        when(() => mockArweaveService.getUniqueUserDriveEntityTxs(any(),
            maxRetries: any(named: 'maxRetries'))).thenAnswer((_) async => []);
        final isExisting = await arDriveAuth.isExistingUser(wallet);

        expect(isExisting, false);
      });
    });
    group('userHasPassword method', () {
      // test
      test('Should return true when user has a private drive', () async {
        when(() => mockArweaveService.getFirstPrivateDriveTx(wallet,
                maxRetries: any(named: 'maxRetries')))
            .thenAnswer((_) async => fakePrivateDriveV1);
        final hasPassword = await arDriveAuth.userHasPassword(wallet);

        expect(hasPassword, true);
      });

      test(
          'Should return false when user does not created a password yet when they dont have any ',
          () async {
        when(() => mockArweaveService.getFirstPrivateDriveTx(wallet,
                maxRetries: any(named: 'maxRetries')))
            .thenAnswer((_) async => null);
        final hasPassword = await arDriveAuth.userHasPassword(wallet);

        expect(hasPassword, false);
      });
    });
    group('login method', () {
      group('with biometrics', () {
        final loggedUser = User(
          password: 'password',
          wallet: wallet,
          walletAddress: 'walletAddress',
          walletBalance: BigInt.one,
          cipherKey: SecretKey([]),
          profileType: ProfileType.json,
          errorFetchingIOTokens: false,
        );
        test(
            'should return the user when has private drives and login with sucess. ',
            () async {
          when(() => mockArweaveService.getFirstPrivateDriveTx(wallet,
                  maxRetries: any(named: 'maxRetries')))
              .thenAnswer((_) async => fakePrivateDriveV1);
          when(() => mockUserRepository.getARIOTokens(wallet))
              .thenAnswer((_) async => '0.4');
          when(() => mockUserRepository.getBalance(wallet))
              .thenAnswer((_) async => BigInt.one);
          when(() => mockBiometricAuthentication.isEnabled())
              .thenAnswer((_) async => false);

          when(
            () => mockArDriveCrypto.deriveDriveKey(wallet, any(), any(), '1'),
          ).thenAnswer((invocation) => Future.value(SecretKey([])));

          when(() => mockUserRepository.hasUser())
              .thenAnswer((invocation) => Future.value(true));

          when(
            () => mockArweaveService.getLatestDriveEntityWithId(
              any(),
              driveKey: any(named: 'driveKey'),
              maxRetries: any(named: 'maxRetries'),
              driveOwner: any(named: 'driveOwner'),
            ),
          ).thenAnswer(
            (invocation) => Future.value(
              DriveEntity(
                id: 'some_id',
                rootFolderId: 'some_id',
              ),
            ),
          );

          when(() => mockUserRepository.deleteUser())
              .thenAnswer((invocation) async {});

          when(() => mockUserRepository.saveUser(
                  'password', ProfileType.json, wallet))
              .thenAnswer((invocation) => Future.value(null));

          when(() => mockUserRepository.getUser('password'))
              .thenAnswer((invocation) async => loggedUser);

          final user =
              await arDriveAuth.login(wallet, 'password', ProfileType.json);

          expect(user, isNotNull);
          expect(user, isNotNull);
          expect(user.password, loggedUser.password);
          expect(user.wallet, loggedUser.wallet);
          expect(user.walletAddress, 'walletAddress');
          expect(user.walletBalance, loggedUser.walletBalance);
          expect(user.cipherKey, loggedUser.cipherKey);
          expect(user.profileType, loggedUser.profileType);
        });

        test(
            'should return the user, and save the password on secure storage when has private drives and login with sucess.',
            () async {
          when(
            () => mockArweaveService.getFirstPrivateDriveTx(
              wallet,
              maxRetries: any(named: 'maxRetries'),
            ),
          ).thenAnswer((_) async => fakePrivateDriveV1);

          when(() => mockBiometricAuthentication.isEnabled())
              .thenAnswer((_) async => true);

          when(() => mockSecureKeyValueStore.putString(
                'password',
                'password',
              )).thenAnswer((_) async => true);

          when(
            () => mockArDriveCrypto.deriveDriveKey(wallet, any(), any(), '1'),
          ).thenAnswer((invocation) => Future.value(SecretKey([])));

          when(() => mockUserRepository.hasUser())
              .thenAnswer((invocation) => Future.value(true));
          when(() => mockUserRepository.getARIOTokens(wallet))
              .thenAnswer((_) async => '0.4');
          when(() => mockUserRepository.getBalance(wallet))
              .thenAnswer((_) async => BigInt.one);

          when(
            () => mockArweaveService.getLatestDriveEntityWithId(
              any(),
              driveKey: any(named: 'driveKey'),
              maxRetries: any(named: 'maxRetries'),
              driveOwner: any(named: 'driveOwner'),
            ),
          ).thenAnswer(
            (invocation) => Future.value(
              DriveEntity(
                id: 'some_id',
                rootFolderId: 'some_id',
              ),
            ),
          );

          when(() => mockUserRepository.deleteUser())
              .thenAnswer((invocation) async {});

          when(() => mockUserRepository.saveUser(
                  'password', ProfileType.json, wallet))
              .thenAnswer((invocation) => Future.value(null));

          when(() => mockUserRepository.getUser('password'))
              .thenAnswer((invocation) async => loggedUser);

          final user =
              await arDriveAuth.login(wallet, 'password', ProfileType.json);

          expect(user, isNotNull);
          expect(user, isNotNull);
          expect(user.password, loggedUser.password);
          expect(user.wallet, loggedUser.wallet);
          expect(user.walletAddress, 'walletAddress');
          expect(user.walletBalance, loggedUser.walletBalance);
          expect(user.cipherKey, loggedUser.cipherKey);
          expect(user.profileType, loggedUser.profileType);

          verify(
              () => mockSecureKeyValueStore.putString('password', 'password'));
        });

        test('should return the user when there\'s no private drives',
            () async {
          when(() => mockArweaveService.getFirstPrivateDriveTx(wallet,
                  maxRetries: any(named: 'maxRetries')))
              .thenAnswer((_) async => null);

          when(() => mockBiometricAuthentication.isEnabled())
              .thenAnswer((_) async => false);

          when(() => mockUserRepository.hasUser())
              .thenAnswer((invocation) => Future.value(true));

          when(() => mockUserRepository.getARIOTokens(wallet))
              .thenAnswer((_) async => '0.4');
          when(() => mockUserRepository.getBalance(wallet))
              .thenAnswer((_) async => BigInt.one);

          when(() => mockUserRepository.deleteUser())
              .thenAnswer((invocation) async {});

          when(() => mockUserRepository.saveUser(
                  'password', ProfileType.json, wallet))
              .thenAnswer((invocation) => Future.value(null));

          when(() => mockUserRepository.getUser('password'))
              .thenAnswer((invocation) async => loggedUser);

          final user =
              await arDriveAuth.login(wallet, 'password', ProfileType.json);

          expect(user, isNotNull);
          expect(user, isNotNull);
          expect(user.password, loggedUser.password);
          expect(user.wallet, loggedUser.wallet);
          expect(user.walletAddress, 'walletAddress');
          expect(user.walletBalance, loggedUser.walletBalance);
          expect(user.cipherKey, loggedUser.cipherKey);
          expect(user.profileType, loggedUser.profileType);
        });

        test(
            'should return the user, and save the password on secure storage when there\'s no private drives',
            () async {
          when(() => mockArweaveService.getFirstPrivateDriveTx(wallet,
                  maxRetries: any(named: 'maxRetries')))
              .thenAnswer((_) async => null);

          when(() => mockUserRepository.hasUser())
              .thenAnswer((invocation) => Future.value(true));

          when(() => mockBiometricAuthentication.isEnabled())
              .thenAnswer((_) async => true);

          when(() => mockSecureKeyValueStore.putString(
                'password',
                'password',
              )).thenAnswer((_) async => true);

          when(() => mockUserRepository.deleteUser())
              .thenAnswer((invocation) async {});

          when(() => mockUserRepository.getARIOTokens(wallet))
              .thenAnswer((_) async => '0.4');
          when(() => mockUserRepository.getBalance(wallet))
              .thenAnswer((_) async => BigInt.one);

          when(() => mockUserRepository.saveUser(
                  'password', ProfileType.json, wallet))
              .thenAnswer((invocation) => Future.value(null));

          when(() => mockUserRepository.getUser('password'))
              .thenAnswer((invocation) async => loggedUser);

          final user =
              await arDriveAuth.login(wallet, 'password', ProfileType.json);

          expect(user, isNotNull);
          expect(user, isNotNull);
          expect(user.password, loggedUser.password);
          expect(user.wallet, loggedUser.wallet);
          expect(user.walletAddress, 'walletAddress');
          expect(user.walletBalance, loggedUser.walletBalance);
          expect(user.cipherKey, loggedUser.cipherKey);
          expect(user.profileType, loggedUser.profileType);

          verify(
              () => mockSecureKeyValueStore.putString('password', 'password'));
        });

        test('should return false when password is wrong', () async {
          when(() => mockArweaveService.getFirstPrivateDriveTx(wallet,
                  maxRetries: any(named: 'maxRetries')))
              .thenAnswer((_) async => fakePrivateDriveV1);
          when(
            () => mockArDriveCrypto.deriveDriveKey(wallet, any(), any(), '1'),
          ).thenThrow(Exception('wrong password'));

          expectLater(
              () => arDriveAuth.login(wallet, 'password', ProfileType.json),
              throwsA(isA<WrongPasswordException>()));
        });
      });

      group('without biometrics', () {
        const localizedReason = 'Please authenticate with biometrics';

        final loggedUser = User(
          password: 'password123',
          wallet: wallet,
          walletAddress: 'walletAddress',
          walletBalance: BigInt.one,
          cipherKey: SecretKey([]),
          profileType: ProfileType.json,
          errorFetchingIOTokens: false,
        );

        test(
            'should unlock user when biometric authentication succeeds and user is logged in',
            () async {
          when(() => mockBiometricAuthentication.isEnabled())
              .thenAnswer((_) async => false);
          when(() => mockBiometricAuthentication.authenticate(
                localizedReason: localizedReason,
                useCached: true,
              )).thenAnswer((_) async => true);

          when(() => mockSecureKeyValueStore.getString('password'))
              .thenAnswer((_) async => 'password123');

          when(() => mockUserRepository.hasUser())
              .thenAnswer((_) async => true);

          when(() => mockUserRepository.getARIOTokens(wallet))
              .thenAnswer((_) async => '0.4');
          when(() => mockUserRepository.getBalance(wallet))
              .thenAnswer((_) async => BigInt.one);

          when(() => mockUserRepository.getUser('password123'))
              .thenAnswer((invocation) => Future.value(loggedUser));

          final result = await arDriveAuth.unlockWithBiometrics(
            localizedReason: localizedReason,
          );

          expect(result, isA<User>());

          verify(() => mockBiometricAuthentication.authenticate(
                localizedReason: localizedReason,
                useCached: true,
              ));

          verify(() => mockSecureKeyValueStore.getString('password'));
          verify(() => mockUserRepository.hasUser());
        });

        test(
            'should throw AuthenticationFailedException when biometric authentication succeeds but user is not logged in',
            () async {
          when(() => mockBiometricAuthentication.authenticate(
                localizedReason: localizedReason,
                useCached: true,
              )).thenAnswer((_) async => true);

          when(() => mockUserRepository.hasUser())
              .thenAnswer((_) async => false);

          expect(
            arDriveAuth.unlockWithBiometrics(localizedReason: localizedReason),
            throwsA(isA<WrongPasswordException>()),
          );

          verifyNever(() => mockBiometricAuthentication.authenticate(
                localizedReason: localizedReason,
                useCached: true,
              ));

          verify(() => mockUserRepository.hasUser());
          verifyNever(() => mockSecureKeyValueStore.getString('password'));
        });

        test(
            'should throw AuthenticationFailedException when biometric authentication fails due to user not authenticating',
            () async {
          when(() => mockBiometricAuthentication.authenticate(
                localizedReason: localizedReason,
                useCached: true,
              )).thenAnswer((_) async => false);

          when(() => mockUserRepository.hasUser())
              .thenAnswer((_) async => true);

          expectLater(
            arDriveAuth.unlockWithBiometrics(localizedReason: localizedReason),
            throwsA(isA<WrongPasswordException>()),
          );

          verifyNever(() => mockSecureKeyValueStore.getString('password'));
        });

        // Biometric authentication fails due to password not found,
        // should throw AuthenticationFailedException
        test(
            'should throw AuthenticationUnknownException when biometric authentication fails due to password not found',
            () async {
          when(() => mockBiometricAuthentication.authenticate(
                localizedReason: localizedReason,
                useCached: true,
              )).thenAnswer((_) async => true);

          when(() => mockUserRepository.hasUser())
              .thenAnswer((_) async => true);

          when(() => mockSecureKeyValueStore.getString('password'))
              .thenAnswer((_) async => null);

          expectLater(
            arDriveAuth.unlockWithBiometrics(localizedReason: localizedReason),
            throwsA(isA<AuthenticationUnknownException>()),
          );
        });
      });
    });

    group('unlockUser method', () {
      final unlockedUser = User(
        password: 'password',
        wallet: wallet,
        walletAddress: 'walletAddress',
        walletBalance: BigInt.one,
        cipherKey: SecretKey([]),
        profileType: ProfileType.json,
        errorFetchingIOTokens: false,
      );

      test('should return the user when password is correct', () async {
        when(() => mockBiometricAuthentication.isEnabled())
            .thenAnswer((_) async => false);
        when(() => mockUserRepository.getUser('password'))
            .thenAnswer((invocation) async => unlockedUser);
        when(() => mockUserRepository.getARIOTokens(wallet))
            .thenAnswer((_) async => '0.4');
        when(() => mockUserRepository.getBalance(wallet))
            .thenAnswer((_) async => BigInt.one);

        when(() => mockBiometricAuthentication.isEnabled())
            .thenAnswer((_) async => false);

        final user = await arDriveAuth.unlockUser(password: 'password');

        expect(user, isNotNull);
        expect(arDriveAuth.currentUser, isNotNull);
        expect(user.password, unlockedUser.password);
        expect(user.wallet, unlockedUser.wallet);
        expect(user.walletAddress, 'walletAddress');
        expect(user.walletBalance, unlockedUser.walletBalance);
        expect(user.cipherKey, unlockedUser.cipherKey);
        expect(user.profileType, unlockedUser.profileType);
      });

      test('should throw when password is not correct', () async {
        when(() => mockUserRepository.getUser('password'))
            .thenThrow(ProfilePasswordIncorrectException());

        expectLater(() => arDriveAuth.unlockUser(password: 'password'),
            throwsA(isA<WrongPasswordException>()));
      });
    });
    group('logout method', () {
      final unlockedUser = User(
        password: 'password',
        wallet: wallet,
        walletAddress: 'walletAddress',
        walletBalance: BigInt.one,
        cipherKey: SecretKey([]),
        profileType: ProfileType.json,
        errorFetchingIOTokens: false,
      );

      test(
          'should delete the current user and delete it when user is logged in',
          () async {
        when(() => mockBiometricAuthentication.isEnabled())
            .thenAnswer((_) async => false);
        when(() => mockUserRepository.hasUser())
            .thenAnswer((invocation) => Future.value(true));
        when(() => mockUserRepository.getARIOTokens(wallet))
            .thenAnswer((_) async => '0.4');
        when(() => mockUserRepository.getBalance(wallet))
            .thenAnswer((_) async => BigInt.one);

        when(() => mockUserRepository.getUser('password'))
            .thenAnswer((invocation) async => unlockedUser);
        when(() => mockBiometricAuthentication.isEnabled())
            .thenAnswer((_) async => false);

        await arDriveAuth.unlockUser(password: 'password');

        when(() => mockUserRepository.deleteUser())
            .thenAnswer((invocation) async {});
        when(() => mockSecureKeyValueStore.remove('password'))
            .thenAnswer((invocation) => Future.value(true));
        when(() => mockSecureKeyValueStore.remove('biometricEnabled'))
            .thenAnswer((invocation) => Future.value(true));
        when(() => mockDatabaseHelpers.deleteAllTables())
            .thenAnswer((invocation) async {});

        await arDriveAuth.logout();

        expect(() => arDriveAuth.currentUser,
            throwsA(isA<AuthenticationUserIsNotLoggedInException>()));
        verify(() => mockSecureKeyValueStore.remove('password')).called(1);
        verify(() => mockSecureKeyValueStore.remove('biometricEnabled'))
            .called(1);
        verify(() => mockDatabaseHelpers.deleteAllTables()).called(1);
      });

      /// This is for the case when has user is true but the user is not logged in
      /// one example is the forget wallet page before the user is logged in
      test(
          'should delete the current user and delete it when user is not logged',
          () async {
        when(() => mockUserRepository.hasUser())
            .thenAnswer((invocation) => Future.value(false));
        when(() => mockDatabaseHelpers.deleteAllTables())
            .thenAnswer((invocation) async {});
        when(() => mockUserRepository.deleteUser())
            .thenAnswer((invocation) async {});

        await arDriveAuth.logout();

        verifyNever(() => mockSecureKeyValueStore.remove('password'));
        verifyNever(() => mockSecureKeyValueStore.remove('biometricEnabled'));
        verify(() => mockDatabaseHelpers.deleteAllTables()).called(1);
        verify(() => mockUserRepository.deleteUser()).called(1);
        expect(() => arDriveAuth.currentUser,
            throwsA(isA<AuthenticationUserIsNotLoggedInException>()));
      });

      test('testing login + logout', () async {
        final loggedUser = User(
          password: 'password',
          wallet: wallet,
          walletAddress: 'walletAddress',
          walletBalance: BigInt.one,
          cipherKey: SecretKey([]),
          profileType: ProfileType.json,
          errorFetchingIOTokens: false,
        );
        when(
          () => mockArweaveService.getFirstPrivateDriveTx(
            wallet,
            maxRetries: any(named: 'maxRetries'),
          ),
        ).thenAnswer((_) async => fakePrivateDriveV1);
        when(() => mockBiometricAuthentication.isEnabled())
            .thenAnswer((_) async => false);
        when(() => mockUserRepository.getARIOTokens(wallet))
            .thenAnswer((_) async => '0.4');
        when(() => mockUserRepository.getBalance(wallet))
            .thenAnswer((_) async => BigInt.one);

        when(
          () => mockArDriveCrypto.deriveDriveKey(wallet, any(), any(), '1'),
        ).thenAnswer((invocation) => Future.value(SecretKey([])));
        when(() => mockUserRepository.hasUser())
            .thenAnswer((invocation) => Future.value(true));
        when(
          () => mockArweaveService.getLatestDriveEntityWithId(
            any(),
            driveKey: any(named: 'driveKey'),
            maxRetries: any(named: 'maxRetries'),
            driveOwner: any(named: 'driveOwner'),
          ),
        ).thenAnswer((invocation) => Future.value(DriveEntity(
              id: 'some_id',
              rootFolderId: 'some_id',
            )));
        when(() => mockUserRepository.deleteUser())
            .thenAnswer((invocation) async {});
        when(() => mockUserRepository.saveUser(
                'password', ProfileType.json, wallet))
            .thenAnswer((invocation) => Future.value(null));
        when(() => mockUserRepository.getUser('password'))
            .thenAnswer((invocation) async => loggedUser);
        when(() => mockUserRepository.deleteUser())
            .thenAnswer((invocation) async {});
        when(() => mockSecureKeyValueStore.remove('password'))
            .thenAnswer((invocation) => Future.value(true));
        when(() => mockSecureKeyValueStore.remove('biometricEnabled'))
            .thenAnswer((invocation) => Future.value(true));
        when(() => mockDatabaseHelpers.deleteAllTables())
            .thenAnswer((invocation) async {});

        await arDriveAuth.login(wallet, 'password', ProfileType.json);

        verify(() => mockUserRepository.deleteUser()).called(1);

        await arDriveAuth.logout();

        expect(() => arDriveAuth.currentUser,
            throwsA(isA<AuthenticationUserIsNotLoggedInException>()));
        verify(() => mockSecureKeyValueStore.remove('password')).called(1);
        verify(() => mockSecureKeyValueStore.remove('biometricEnabled'))
            .called(1);
        verify(() => mockDatabaseHelpers.deleteAllTables()).called(1);
        verify(() => mockUserRepository.deleteUser()).called(1);
      });
    });
    group('onAuthStateChanged method', () {
      late User loggedUser;

      setUp(() {
        loggedUser = User(
          password: 'password',
          wallet: wallet,
          walletAddress: 'walletAddress',
          walletBalance: BigInt.one,
          cipherKey: SecretKey([]),
          profileType: ProfileType.json,
          errorFetchingIOTokens: false,
        );
        when(() => mockBiometricAuthentication.isEnabled())
            .thenAnswer((_) async => false);
        when(() => mockArweaveService.getFirstPrivateDriveTx(wallet,
                maxRetries: any(named: 'maxRetries')))
            .thenAnswer((_) async => fakePrivateDriveV1);
        when(
          () => mockArDriveCrypto.deriveDriveKey(wallet, any(), any(), '1'),
        ).thenAnswer((invocation) => Future.value(SecretKey([])));
        when(() => mockUserRepository.hasUser())
            .thenAnswer((invocation) => Future.value(true));
        when(() => mockUserRepository.getARIOTokens(wallet))
            .thenAnswer((_) async => '0.4');
        when(() => mockUserRepository.getBalance(wallet))
            .thenAnswer((_) async => BigInt.one);

        when(
          () => mockArweaveService.getLatestDriveEntityWithId(
            any(),
            driveKey: any(named: 'driveKey'),
            maxRetries: any(named: 'maxRetries'),
            driveOwner: any(named: 'driveOwner'),
          ),
        ).thenAnswer((invocation) => Future.value(DriveEntity(
              id: 'some_id',
              rootFolderId: 'some_id',
            )));
        when(() => mockUserRepository.deleteUser())
            .thenAnswer((invocation) async {});
        when(() => mockUserRepository.saveUser(
                'password', ProfileType.json, wallet))
            .thenAnswer((invocation) => Future.value(null));

        when(() => mockUserRepository.getUser('password'))
            .thenAnswer((invocation) async => loggedUser);

        when(() => mockBiometricAuthentication.isEnabled())
            .thenAnswer((_) async => false);
      });
      test('should change the state when user logs in', () async {
        when(() => mockBiometricAuthentication.isEnabled())
            .thenAnswer((_) async => false);

        final loggedUser = User(
          password: 'password',
          wallet: wallet,
          walletAddress: 'walletAddress',
          walletBalance: BigInt.one,
          cipherKey: SecretKey([]),
          profileType: ProfileType.json,
          errorFetchingIOTokens: false,
        );

        arDriveAuth.onAuthStateChanged().listen((user) {
          expect(user, isNotNull);
          expect(user!.password, loggedUser.password);
          expect(user.wallet, loggedUser.wallet);
          expect(user.walletAddress, 'walletAddress');
          expect(user.walletBalance, loggedUser.walletBalance);
          expect(user.cipherKey, loggedUser.cipherKey);
          expect(user.profileType, loggedUser.profileType);
        });

        await arDriveAuth.login(wallet, 'password', ProfileType.json);
      });

      test('should change the state when user logs out', () async {
        when(() => mockBiometricAuthentication.isEnabled())
            .thenAnswer((_) async => false);
        when(() => mockUserRepository.hasUser())
            .thenAnswer((invocation) => Future.value(true));
        when(() => mockUserRepository.getUser('password'))
            .thenAnswer((invocation) async => loggedUser);

        await arDriveAuth.unlockUser(password: 'password');

        when(() => mockUserRepository.deleteUser())
            .thenAnswer((invocation) async {});
        when(() => mockSecureKeyValueStore.remove('password'))
            .thenAnswer((invocation) => Future.value(true));
        when(() => mockSecureKeyValueStore.remove('biometricEnabled'))
            .thenAnswer((invocation) => Future.value(true));
        when(() => mockDatabaseHelpers.deleteAllTables())
            .thenAnswer((invocation) async {});

        arDriveAuth.onAuthStateChanged().listen((user) {
          expect(user, isNull);
        });

        await arDriveAuth.logout();
      });
    });
  });

  group('getWalletAddress method', () {
    test('should return the wallet address when user is logged in', () async {
      const publicKey =
          'y6tP8PVR5VSOsouFIDFBIDAAQ19b25pQRcDrdYDyBr7dtW5sKHHpcrA-I1scOk5H_ZX22_4E5T568SToox_y5XeBJ3nw9kB8HzgdmQyMnEBnb050NvKv2w47vD7I0I7qrRSqJ8dt3Q3UPZvkys9sm2HEpoMaaJ-Fx44ww1CYs5U2KXI-BSpwA7SQE3eRIESZ-kD4D9TYt5ykuslRKOM1lZSiRxGqKfpnutKNZ5tdl5-d9Z4eZ2qeMETevbhXUjh8p7sJbWb02hHozNJUBawuZ3xQ2KRQqymFM9GqKE8EnHIVvR2V1LIkbcWbEIuSpqviwLschZpQ9pbTljMOqKR7_ox_199qyU9z4nnJsGLBZnv5ilGs1J5dlCitDlRCMJ53A9e5GojEzKOpzaFfHlei9DD2MUN8cKc7_pQuFuhNwkMwzKduekmFgRdvIr0ZlyRiG02CX3txpXjqw5iBYjhs4fQhNE0nj9FzBnEm4z_NltyTAf8W6TbKN40AFn__A5-wUDQ1XdA7bgPfz4UMDyldkHLXTzdgn5jg2-233IO5PK0xOes0jMRdR1d0jqF38wldgWtBt6oDk8jic6hCUCP29zoYqlNRcJHKFRDWZaZMkmVQON6-EvilC7-sGiKsbcTIhRw-wuC0guQFHSUiJpJZB9hWmMHejGqME0mCin6gQFM';
      const expectedWalletAddress =
          'e3a1dzQ1DlGBHa7hjOzTtODLLHwwRsbq0evWvJMqkkc';

      when(() => mockUserRepository.getOwnerOfDefaultProfile())
          .thenAnswer((_) async => publicKey);

      final walletAddress = await arDriveAuth.getWalletAddress();

      expect(walletAddress, expectedWalletAddress);
    });

    test('should return null when user is not logged in', () async {
      when(() => mockUserRepository.getOwnerOfDefaultProfile())
          .thenAnswer((_) async => null);

      final walletAddress = await arDriveAuth.getWalletAddress();

      expect(walletAddress, null);
    });

    group('refreshBalance method', () {
      test('should update current user balance and notify listeners', () async {
        // Arrange
        final initialBalance = BigInt.one;
        final updatedBalance = BigInt.two;
        final initialUser = User(
          password: 'password',
          wallet: wallet,
          walletAddress: 'walletAddress',
          walletBalance: initialBalance,
          cipherKey: SecretKey([]),
          profileType: ProfileType.json,
          errorFetchingIOTokens: false,
        );
        // Updated user with new balance
        final updatedUser = initialUser.copyWith(walletBalance: updatedBalance);

        arDriveAuth.currentUser = initialUser;

        when(() => mockUserRepository.getBalance(wallet))
            .thenAnswer((_) async => updatedBalance);
        when(() => mockUserRepository.getARIOTokens(wallet))
            .thenAnswer((_) async => '0.4');

        // Act
        await arDriveAuth.refreshBalance();

        // Assert
        expect(arDriveAuth.currentUser.walletBalance, equals(updatedBalance));
        expect(arDriveAuth.currentUser.errorFetchingIOTokens, false);
        verify(() => mockUserRepository.getBalance(wallet)).called(1);

        // Verify that listeners are notified
        arDriveAuth.onAuthStateChanged().listen((user) {
          expect(user, equals(updatedUser));
        });
      });
    });
  });
}

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/profile_source.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/metadata_cache.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stash_memory/stash_memory.dart';

import '../test_utils/utils.dart';

class TransactionCommonMixinFake extends Fake
    implements TransactionCommonMixin {}

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
    // register call back for test drive entity
    registerFallbackValue(DriveEntity(
      id: 'some_id',
      rootFolderId: 'some_id',
    ));
  });

  // test `ArDriveAuth`
  group('ArDriveAuth testing isUserLoggedIn method', () {
    test('Should return true when user is logged in', () async {
      // arrange
      when(() => mockUserRepository.hasUser()).thenAnswer((_) async => true);
      // act
      final isLoggedIn = await arDriveAuth.isUserLoggedIn();

      // assert
      expect(isLoggedIn, true);
    });

    test('Should return false when user is not logged in', () async {
      // arrange
      when(() => mockUserRepository.hasUser()).thenAnswer((_) async => false);
      // act
      final isLoggedIn = await arDriveAuth.isUserLoggedIn();

      // assert
      expect(isLoggedIn, false);
    });
  });

  group('ArDriveAuth testing isExistingUser method', () {
    // test
    test('Should return true when user is existing', () async {
      // arrange
      when(() => mockArweaveService.getUniqueUserDriveEntityTxs(any(),
              maxRetries: any(named: 'maxRetries')))
          .thenAnswer((_) async => [TransactionCommonMixinFake()]);
      // act
      final isExisting = await arDriveAuth.isExistingUser(wallet);

      // assert
      expect(isExisting, true);
    });

    test('Should return false when user is not existing', () async {
      // arrange
      when(() => mockArweaveService.getUniqueUserDriveEntityTxs(any(),
          maxRetries: any(named: 'maxRetries'))).thenAnswer((_) async => []);
      // act
      final isExisting = await arDriveAuth.isExistingUser(wallet);

      // assert
      expect(isExisting, false);
    });
  });
  group('ArDriveAuth testing userHasPassword method', () {
    // test
    test('Should return true when user has a private drive', () async {
      // arrange
      when(() => mockArweaveService.getFirstPrivateDriveTxId(wallet,
              maxRetries: any(named: 'maxRetries')))
          .thenAnswer((_) async => 'some_id');
      // act
      final hasPassword = await arDriveAuth.userHasPassword(wallet);

      // assert
      expect(hasPassword, true);
    });

    test(
        'Should return false when user does not created a password yet when they dont have any ',
        () async {
      // arrange
      when(() => mockArweaveService.getFirstPrivateDriveTxId(wallet,
          maxRetries: any(named: 'maxRetries'))).thenAnswer((_) async => null);
      // act
      final hasPassword = await arDriveAuth.userHasPassword(wallet);

      // assert
      expect(hasPassword, false);
    });
  });

  group('testing if getFirstPrivateDriveTxId is called only once', () {
    final loggedUser = User(
      password: 'password',
      wallet: wallet,
      walletAddress: 'walletAddress',
      walletBalance: BigInt.one,
      cipherKey: SecretKey([]),
      profileType: ProfileType.json,
      profileSource: ProfileSource(type: ProfileSourceType.standalone),
    );

    /// For this test we'll call the same method twice to validate if the
    /// getFirstPrivateDriveTxId is called only once

    test(
        'should call getFirstPrivateDriveTxId only once when has private drives and login with sucess. ',
        () async {
      // arrange
      when(() => mockArweaveService.getFirstPrivateDriveTxId(wallet,
              maxRetries: any(named: 'maxRetries')))
          .thenAnswer((_) async => 'some_id');

      // biometrics is not enabled
      when(() => mockBiometricAuthentication.isEnabled())
          .thenAnswer((_) async => false);

      // mock cripto derive drive key
      when(
        () => mockArDriveCrypto.deriveDriveKey(
          wallet,
          any(),
          any(),
        ),
      ).thenAnswer((invocation) => Future.value(SecretKey([])));

      when(() => mockUserRepository.hasUser())
          .thenAnswer((invocation) => Future.value(true));

      when(() => mockArweaveService.getLatestDriveEntityWithId(
              any(), any(), any()))
          .thenAnswer((invocation) => Future.value(DriveEntity(
                id: 'some_id',
                rootFolderId: 'some_id',
              )));

      when(() => mockUserRepository.deleteUser())
          .thenAnswer((invocation) async {});

      when(() => mockUserRepository.saveUser(
          'password',
          ProfileType.json,
          ProfileSource(type: ProfileSourceType.standalone),
          wallet)).thenAnswer((invocation) => Future.value(null));

      when(() => mockUserRepository.getUser('password'))
          .thenAnswer((invocation) async => loggedUser);

      // act
      await arDriveAuth.login(wallet, 'password', ProfileType.json,
          ProfileSource(type: ProfileSourceType.standalone));
      await arDriveAuth.login(wallet, 'password', ProfileType.json,
          ProfileSource(type: ProfileSourceType.standalone));

      // assert
      verify(() => mockArweaveService.getFirstPrivateDriveTxId(wallet,
          maxRetries: any(named: 'maxRetries'))).called(1);
    });

    test(
        'should call getFirstPrivateDriveTxId only once when has private drives and login with sucess. ',
        () async {
      when(() => mockArweaveService.getFirstPrivateDriveTxId(wallet,
              maxRetries: any(named: 'maxRetries')))
          .thenAnswer((_) async => 'some_id');
      // act
      await arDriveAuth.userHasPassword(wallet);
      await arDriveAuth.userHasPassword(wallet);

      // assert
      verify(() => mockArweaveService.getFirstPrivateDriveTxId(wallet,
          maxRetries: any(named: 'maxRetries'))).called(1);
    });
  });

  group('ArDriveAuth testing login method without biometrics', () {
    final loggedUser = User(
      password: 'password',
      wallet: wallet,
      walletAddress: 'walletAddress',
      walletBalance: BigInt.one,
      cipherKey: SecretKey([]),
      profileType: ProfileType.json,
      profileSource: ProfileSource(type: ProfileSourceType.standalone),
    );
    test(
        'should return the user when has private drives and login with sucess. ',
        () async {
      // arrange
      when(() => mockArweaveService.getFirstPrivateDriveTxId(wallet,
              maxRetries: any(named: 'maxRetries')))
          .thenAnswer((_) async => 'some_id');

      // biometrics is not enabled
      when(() => mockBiometricAuthentication.isEnabled())
          .thenAnswer((_) async => false);

      // mock cripto derive drive key
      when(
        () => mockArDriveCrypto.deriveDriveKey(
          wallet,
          any(),
          any(),
        ),
      ).thenAnswer((invocation) => Future.value(SecretKey([])));

      when(() => mockUserRepository.hasUser())
          .thenAnswer((invocation) => Future.value(true));

      when(() => mockArweaveService.getLatestDriveEntityWithId(
              any(), any(), any()))
          .thenAnswer((invocation) => Future.value(DriveEntity(
                id: 'some_id',
                rootFolderId: 'some_id',
              )));

      when(() => mockUserRepository.deleteUser())
          .thenAnswer((invocation) async {});

      when(() => mockUserRepository.saveUser(
          'password',
          ProfileType.json,
          ProfileSource(type: ProfileSourceType.standalone),
          wallet)).thenAnswer((invocation) => Future.value(null));

      when(() => mockUserRepository.getUser('password'))
          .thenAnswer((invocation) async => loggedUser);

      // act
      final user = await arDriveAuth.login(wallet, 'password', ProfileType.json,
          ProfileSource(type: ProfileSourceType.standalone));

      // assert
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
      // arrange
      when(() => mockArweaveService.getFirstPrivateDriveTxId(wallet,
              maxRetries: any(named: 'maxRetries')))
          .thenAnswer((_) async => 'some_id');

      // biometrics is enabled
      when(() => mockBiometricAuthentication.isEnabled())
          .thenAnswer((_) async => true);

      when(() => mockSecureKeyValueStore.putString(
            'password',
            'password',
          )).thenAnswer((_) async => true);

      // mock cripto derive drive key
      when(
        () => mockArDriveCrypto.deriveDriveKey(
          wallet,
          any(),
          any(),
        ),
      ).thenAnswer((invocation) => Future.value(SecretKey([])));

      when(() => mockUserRepository.hasUser())
          .thenAnswer((invocation) => Future.value(true));

      when(() => mockArweaveService.getLatestDriveEntityWithId(
              any(), any(), any()))
          .thenAnswer((invocation) => Future.value(DriveEntity(
                id: 'some_id',
                rootFolderId: 'some_id',
              )));

      when(() => mockUserRepository.deleteUser())
          .thenAnswer((invocation) async {});

      when(() => mockUserRepository.saveUser(
          'password',
          ProfileType.json,
          ProfileSource(type: ProfileSourceType.standalone),
          wallet)).thenAnswer((invocation) => Future.value(null));

      when(() => mockUserRepository.getUser('password'))
          .thenAnswer((invocation) async => loggedUser);

      // act
      final user = await arDriveAuth.login(wallet, 'password', ProfileType.json,
          ProfileSource(type: ProfileSourceType.standalone));

      // assert
      expect(user, isNotNull);
      expect(user, isNotNull);
      expect(user.password, loggedUser.password);
      expect(user.wallet, loggedUser.wallet);
      expect(user.walletAddress, 'walletAddress');
      expect(user.walletBalance, loggedUser.walletBalance);
      expect(user.cipherKey, loggedUser.cipherKey);
      expect(user.profileType, loggedUser.profileType);

      // calls the secure storage
      verify(() => mockSecureKeyValueStore.putString('password', 'password'));
    });

    test('should return the user when there\'s no private drives', () async {
      // arrange
      // no private drives
      when(() => mockArweaveService.getFirstPrivateDriveTxId(wallet,
          maxRetries: any(named: 'maxRetries'))).thenAnswer((_) async => null);

      // biometrics is not enabled
      when(() => mockBiometricAuthentication.isEnabled())
          .thenAnswer((_) async => false);

      when(() => mockUserRepository.hasUser())
          .thenAnswer((invocation) => Future.value(true));

      when(() => mockUserRepository.deleteUser())
          .thenAnswer((invocation) async {});

      when(() => mockUserRepository.saveUser(
          'password',
          ProfileType.json,
          ProfileSource(type: ProfileSourceType.standalone),
          wallet)).thenAnswer((invocation) => Future.value(null));

      when(() => mockUserRepository.getUser('password'))
          .thenAnswer((invocation) async => loggedUser);

      // act
      final user = await arDriveAuth.login(wallet, 'password', ProfileType.json,
          ProfileSource(type: ProfileSourceType.standalone));

      // assert
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
      // arrange
      // no private drives
      when(() => mockArweaveService.getFirstPrivateDriveTxId(wallet,
          maxRetries: any(named: 'maxRetries'))).thenAnswer((_) async => null);

      when(() => mockUserRepository.hasUser())
          .thenAnswer((invocation) => Future.value(true));

      // biometrics enabled
      when(() => mockBiometricAuthentication.isEnabled())
          .thenAnswer((_) async => true);

      when(() => mockSecureKeyValueStore.putString(
            'password',
            'password',
          )).thenAnswer((_) async => true);

      when(() => mockUserRepository.deleteUser())
          .thenAnswer((invocation) async {});

      when(() => mockUserRepository.saveUser(
          'password',
          ProfileType.json,
          ProfileSource(type: ProfileSourceType.standalone),
          wallet)).thenAnswer((invocation) => Future.value(null));

      when(() => mockUserRepository.getUser('password'))
          .thenAnswer((invocation) async => loggedUser);

      // act
      final user = await arDriveAuth.login(wallet, 'password', ProfileType.json,
          ProfileSource(type: ProfileSourceType.standalone));

      // assert
      expect(user, isNotNull);
      expect(user, isNotNull);
      expect(user.password, loggedUser.password);
      expect(user.wallet, loggedUser.wallet);
      expect(user.walletAddress, 'walletAddress');
      expect(user.walletBalance, loggedUser.walletBalance);
      expect(user.cipherKey, loggedUser.cipherKey);
      expect(user.profileType, loggedUser.profileType);

      // calls the secure storage
      verify(() => mockSecureKeyValueStore.putString('password', 'password'));
    });

    test('should return false when password is wrong', () async {
      // arrange
      when(() => mockArweaveService.getFirstPrivateDriveTxId(wallet,
              maxRetries: any(named: 'maxRetries')))
          .thenAnswer((_) async => 'some_id');
      // mock cripto derive drive key
      when(
        () => mockArDriveCrypto.deriveDriveKey(
          wallet,
          any(),
          any(),
        ),
      ).thenThrow(Exception('wrong password'));

      // assert
      expectLater(
          () => arDriveAuth.login(wallet, 'password', ProfileType.json,
              ProfileSource(type: ProfileSourceType.standalone)),
          throwsA(isA<AuthenticationFailedException>()));
    });
  });

  group('testing ArDriveAuth unlockUser method', () {
    final unlockedUser = User(
      password: 'password',
      wallet: wallet,
      walletAddress: 'walletAddress',
      walletBalance: BigInt.one,
      cipherKey: SecretKey([]),
      profileType: ProfileType.json,
      profileSource: ProfileSource(type: ProfileSourceType.standalone),
    );

    test('should return the user when password is correct', () async {
      // arrange
      when(() => mockUserRepository.getUser('password'))
          .thenAnswer((invocation) async => unlockedUser);

      // act
      final user = await arDriveAuth.unlockUser(password: 'password');

      // assert
      // compare user
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
      // arrange
      when(() => mockUserRepository.getUser('password'))
          .thenThrow(Exception('wrong password'));

      expectLater(() => arDriveAuth.unlockUser(password: 'password'),
          throwsA(isA<AuthenticationFailedException>()));
    });
  });

  group('testing if getFirstPrivateDriveTxId is called only once', () {});

  group('testing ArDriveAuth logout method', () {
    final unlockedUser = User(
      password: 'password',
      wallet: wallet,
      walletAddress: 'walletAddress',
      walletBalance: BigInt.one,
      cipherKey: SecretKey([]),
      profileType: ProfileType.json,
      profileSource: ProfileSource(type: ProfileSourceType.standalone),
    );

    test('should delete the current user and delete it when user is logged in',
        () async {
      when(() => mockUserRepository.hasUser())
          .thenAnswer((invocation) => Future.value(true));
      when(() => mockUserRepository.getUser('password'))
          .thenAnswer((invocation) async => unlockedUser);

      // act
      await arDriveAuth.unlockUser(password: 'password');

      // arrange
      when(() => mockUserRepository.deleteUser())
          .thenAnswer((invocation) async {});
      when(() => mockSecureKeyValueStore.remove('password'))
          .thenAnswer((invocation) => Future.value(true));
      when(() => mockSecureKeyValueStore.remove('biometricEnabled'))
          .thenAnswer((invocation) => Future.value(true));
      when(() => mockDatabaseHelpers.deleteAllTables())
          .thenAnswer((invocation) async {});

      // act
      await arDriveAuth.logout();

      // assert
      expect(() => arDriveAuth.currentUser,
          throwsA(isA<AuthenticationUserIsNotLoggedInException>()));
      expect(arDriveAuth.firstPrivateDriveTxId, isNull);
      verify(() => mockSecureKeyValueStore.remove('password')).called(1);
      verify(() => mockSecureKeyValueStore.remove('biometricEnabled'))
          .called(1);
      verify(() => mockDatabaseHelpers.deleteAllTables()).called(1);
    });

    /// This is for the case when has user is true but the user is not logged in
    /// one example is the forget wallet page before the user is logged in
    test('should delete the current user and delete it when user is not logged',
        () async {
      when(() => mockUserRepository.hasUser())
          .thenAnswer((invocation) => Future.value(false));

      // arrange
      when(() => mockDatabaseHelpers.deleteAllTables())
          .thenAnswer((invocation) async {});

      // act
      await arDriveAuth.logout();

      // assert
      verifyNever(() => mockSecureKeyValueStore.remove('password'));
      verifyNever(() => mockSecureKeyValueStore.remove('biometricEnabled'));
      verify(() => mockDatabaseHelpers.deleteAllTables()).called(1);
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
        profileSource: ProfileSource(type: ProfileSourceType.standalone),
      );
      // arrange login
      when(() => mockArweaveService.getFirstPrivateDriveTxId(wallet,
              maxRetries: any(named: 'maxRetries')))
          .thenAnswer((_) async => 'some_id');

      // biometrics is not enabled
      when(() => mockBiometricAuthentication.isEnabled())
          .thenAnswer((_) async => false);

      // mock cripto derive drive key
      when(
        () => mockArDriveCrypto.deriveDriveKey(
          wallet,
          any(),
          any(),
        ),
      ).thenAnswer((invocation) => Future.value(SecretKey([])));

      when(() => mockUserRepository.hasUser())
          .thenAnswer((invocation) => Future.value(true));

      when(() => mockArweaveService.getLatestDriveEntityWithId(
              any(), any(), any()))
          .thenAnswer((invocation) => Future.value(DriveEntity(
                id: 'some_id',
                rootFolderId: 'some_id',
              )));

      when(() => mockUserRepository.deleteUser())
          .thenAnswer((invocation) async {});

      when(() => mockUserRepository.saveUser(
          'password',
          ProfileType.json,
          ProfileSource(type: ProfileSourceType.standalone),
          wallet)).thenAnswer((invocation) => Future.value(null));

      when(() => mockUserRepository.getUser('password'))
          .thenAnswer((invocation) async => loggedUser);

      /// arrange logout
      when(() => mockUserRepository.deleteUser())
          .thenAnswer((invocation) async {});
      when(() => mockSecureKeyValueStore.remove('password'))
          .thenAnswer((invocation) => Future.value(true));
      when(() => mockSecureKeyValueStore.remove('biometricEnabled'))
          .thenAnswer((invocation) => Future.value(true));
      when(() => mockDatabaseHelpers.deleteAllTables())
          .thenAnswer((invocation) async {});

      await arDriveAuth.login(wallet, 'password', ProfileType.json,
          ProfileSource(type: ProfileSourceType.standalone));

      await arDriveAuth.logout();

      /// verifies that we cleaned up the user
      expect(arDriveAuth.firstPrivateDriveTxId, isNull);
      expect(() => arDriveAuth.currentUser,
          throwsA(isA<AuthenticationUserIsNotLoggedInException>()));
      verify(() => mockSecureKeyValueStore.remove('password')).called(1);
      verify(() => mockSecureKeyValueStore.remove('biometricEnabled'))
          .called(1);
      verify(() => mockDatabaseHelpers.deleteAllTables()).called(1);
      verify(() => mockUserRepository.deleteUser()).called(1);
    });
  });

  group('testing ArDriveAuth onAuthStateChanged method', () {
    late User loggedUser;

    setUp(() {
      loggedUser = User(
        password: 'password',
        wallet: wallet,
        walletAddress: 'walletAddress',
        walletBalance: BigInt.one,
        cipherKey: SecretKey([]),
        profileType: ProfileType.json,
        profileSource: ProfileSource(type: ProfileSourceType.standalone),
      );
      // arrange
      when(() => mockArweaveService.getFirstPrivateDriveTxId(wallet,
              maxRetries: any(named: 'maxRetries')))
          .thenAnswer((_) async => 'some_id');
      // mock cripto derive drive key
      when(
        () => mockArDriveCrypto.deriveDriveKey(
          wallet,
          any(),
          any(),
        ),
      ).thenAnswer((invocation) => Future.value(SecretKey([])));
      when(() => mockUserRepository.hasUser())
          .thenAnswer((invocation) => Future.value(true));
      when(() => mockArweaveService.getLatestDriveEntityWithId(
              any(), any(), any()))
          .thenAnswer((invocation) => Future.value(DriveEntity(
                id: 'some_id',
                rootFolderId: 'some_id',
              )));
      when(() => mockUserRepository.deleteUser())
          .thenAnswer((invocation) async {});
      when(() => mockUserRepository.saveUser(
          'password',
          ProfileType.json,
          ProfileSource(type: ProfileSourceType.standalone),
          wallet)).thenAnswer((invocation) => Future.value(null));

      when(() => mockUserRepository.getUser('password'))
          .thenAnswer((invocation) async => loggedUser);
    });
    test('should change the state when user logs in', () async {
      // arrange
      // biometrics disabled
      when(() => mockBiometricAuthentication.isEnabled())
          .thenAnswer((_) async => false);

      final loggedUser = User(
        password: 'password',
        wallet: wallet,
        walletAddress: 'walletAddress',
        walletBalance: BigInt.one,
        cipherKey: SecretKey([]),
        profileType: ProfileType.json,
        profileSource: ProfileSource(type: ProfileSourceType.standalone),
      );

      // act
      arDriveAuth.onAuthStateChanged().listen((user) {
        // assert
        expect(user, isNotNull);
        expect(user!.password, loggedUser.password);
        expect(user.wallet, loggedUser.wallet);
        expect(user.walletAddress, 'walletAddress');
        expect(user.walletBalance, loggedUser.walletBalance);
        expect(user.cipherKey, loggedUser.cipherKey);
        expect(user.profileType, loggedUser.profileType);
      });

      await arDriveAuth.login(wallet, 'password', ProfileType.json,
          ProfileSource(type: ProfileSourceType.standalone));
    });

    test('should change the state when user logs out', () async {
      when(() => mockUserRepository.hasUser())
          .thenAnswer((invocation) => Future.value(true));
      when(() => mockUserRepository.getUser('password'))
          .thenAnswer((invocation) async => loggedUser);

      // act
      await arDriveAuth.unlockUser(password: 'password');

      // arrange
      when(() => mockUserRepository.deleteUser())
          .thenAnswer((invocation) async {});
      when(() => mockSecureKeyValueStore.remove('password'))
          .thenAnswer((invocation) => Future.value(true));
      when(() => mockSecureKeyValueStore.remove('biometricEnabled'))
          .thenAnswer((invocation) => Future.value(true));
      when(() => mockDatabaseHelpers.deleteAllTables())
          .thenAnswer((invocation) async {});

      // act
      arDriveAuth.onAuthStateChanged().listen((user) {
        // assert
        expect(user, isNull);
      });

      await arDriveAuth.logout();
    });
  });

  group('unlockWithBiometrics', () {
    const localizedReason = 'Please authenticate with biometrics';

    final loggedUser = User(
      password: 'password123',
      wallet: wallet,
      walletAddress: 'walletAddress',
      walletBalance: BigInt.one,
      cipherKey: SecretKey([]),
      profileType: ProfileType.json,
      profileSource: ProfileSource(type: ProfileSourceType.standalone),
    );

    test(
        'should unlock user when biometric authentication succeeds and user is logged in',
        () async {
      // Mock dependencies
      when(() => mockBiometricAuthentication.authenticate(
            localizedReason: localizedReason,
            useCached: true,
          )).thenAnswer((_) async => true);

      when(() => mockSecureKeyValueStore.getString('password'))
          .thenAnswer((_) async => 'password123');

      when(() => mockUserRepository.hasUser()).thenAnswer((_) async => true);

      when(() => mockUserRepository.getUser('password123'))
          .thenAnswer((invocation) => Future.value(loggedUser));

      // Invoke the method under test
      final result = await arDriveAuth.unlockWithBiometrics(
        localizedReason: localizedReason,
      );

      // Verify the result
      expect(result, isA<User>());

      // Verify method calls on dependencies
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
      // Mock dependencies
      when(() => mockBiometricAuthentication.authenticate(
            localizedReason: localizedReason,
            useCached: true,
          )).thenAnswer((_) async => true);

      when(() => mockUserRepository.hasUser()).thenAnswer((_) async => false);

      // Invoke the method under test
      expect(
        arDriveAuth.unlockWithBiometrics(localizedReason: localizedReason),
        throwsA(isA<AuthenticationFailedException>()),
      );

      // Verify method calls on dependencies
      verifyNever(() => mockBiometricAuthentication.authenticate(
            localizedReason: localizedReason,
            useCached: true,
          ));

      verify(() => mockUserRepository.hasUser());
      verifyNever(() => mockSecureKeyValueStore.getString('password'));
    });

    // should throw AuthenticationFailedException when biometric authentication fails due to user not authenticating'
    test(
        'should throw AuthenticationFailedException when biometric authentication fails due to user not authenticating',
        () async {
      // Mock dependencies
      when(() => mockBiometricAuthentication.authenticate(
            localizedReason: localizedReason,
            useCached: true,
          )).thenAnswer((_) async => false);

      when(() => mockUserRepository.hasUser()).thenAnswer((_) async => true);

      // Invoke the method under test
      expectLater(
        arDriveAuth.unlockWithBiometrics(localizedReason: localizedReason),
        throwsA(isA<AuthenticationFailedException>()),
      );

      verifyNever(() => mockSecureKeyValueStore.getString('password'));
    });

    // Biometric authentication fails due to password not found,
    // should throw AuthenticationFailedException
    test(
        'should throw AuthenticationUnknownException when biometric authentication fails due to password not found',
        () async {
      // Mock dependencies
      when(() => mockBiometricAuthentication.authenticate(
            localizedReason: localizedReason,
            useCached: true,
          )).thenAnswer((_) async => true);

      when(() => mockUserRepository.hasUser()).thenAnswer((_) async => true);

      when(() => mockSecureKeyValueStore.getString('password'))
          .thenAnswer((_) async => null);

      // Invoke the method under test
      expectLater(
        arDriveAuth.unlockWithBiometrics(localizedReason: localizedReason),
        throwsA(isA<AuthenticationUnknownException>()),
      );
    });
  });
}

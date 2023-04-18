import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/user/user.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';

class TransactionCommonMixinFake extends Fake
    implements TransactionCommonMixin {}

void main() {
  late ArDriveAuth arDriveAuth;
  late MockArweaveService mockArweaveService;
  late MockUserRepository mockUserRepository;
  late MockArDriveCrypto mockArDriveCrypto;
  late MockBiometricAuthentication mockBiometricAuthentication;
  late MockSecureKeyValueStore mockSecureKeyValueStore;

  final wallet = getTestWallet();

  setUp(() {
    mockArweaveService = MockArweaveService();
    mockUserRepository = MockUserRepository();
    mockArDriveCrypto = MockArDriveCrypto();
    mockBiometricAuthentication = MockBiometricAuthentication();
    mockSecureKeyValueStore = MockSecureKeyValueStore();

    arDriveAuth = ArDriveAuth(
      arweave: mockArweaveService,
      userRepository: mockUserRepository,
      crypto: mockArDriveCrypto,
      biometricAuthentication: mockBiometricAuthentication,
      secureKeyValueStore: mockSecureKeyValueStore,
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

  group('ArDriveAuth testing login method without biometrics', () {
    final loggedUser = User(
      password: 'password',
      wallet: wallet,
      walletAddress: 'walletAddress',
      walletBalance: BigInt.one,
      cipherKey: SecretKey([]),
      profileType: ProfileType.json,
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

      when(() =>
              mockUserRepository.saveUser('password', ProfileType.json, wallet))
          .thenAnswer((invocation) => Future.value(null));

      when(() => mockUserRepository.getUser('password'))
          .thenAnswer((invocation) async => loggedUser);

      // act
      final user =
          await arDriveAuth.login(wallet, 'password', ProfileType.json);

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

      when(() =>
              mockUserRepository.saveUser('password', ProfileType.json, wallet))
          .thenAnswer((invocation) => Future.value(null));

      when(() => mockUserRepository.getUser('password'))
          .thenAnswer((invocation) async => loggedUser);

      // act
      final user =
          await arDriveAuth.login(wallet, 'password', ProfileType.json);

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

      when(() =>
              mockUserRepository.saveUser('password', ProfileType.json, wallet))
          .thenAnswer((invocation) => Future.value(null));

      when(() => mockUserRepository.getUser('password'))
          .thenAnswer((invocation) async => loggedUser);

      // act
      final user =
          await arDriveAuth.login(wallet, 'password', ProfileType.json);

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

      when(() =>
              mockUserRepository.saveUser('password', ProfileType.json, wallet))
          .thenAnswer((invocation) => Future.value(null));

      when(() => mockUserRepository.getUser('password'))
          .thenAnswer((invocation) async => loggedUser);

      // act
      final user =
          await arDriveAuth.login(wallet, 'password', ProfileType.json);

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
      expectLater(() => arDriveAuth.login(wallet, 'password', ProfileType.json),
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

  group('testing ArDriveAuth logout method', () {
    test('should delete the current user and delete it', () async {
      // arrange
      when(() => mockUserRepository.deleteUser())
          .thenAnswer((invocation) async {});

      // act
      await arDriveAuth.logout();

      // assert
      verify(() => mockUserRepository.deleteUser()).called(1);
      expect(() => arDriveAuth.currentUser,
          throwsA(isA<AuthenticationUserIsNotLoggedInException>()));
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
      when(() =>
              mockUserRepository.saveUser('password', ProfileType.json, wallet))
          .thenAnswer((invocation) => Future.value(null));

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

      await arDriveAuth.login(wallet, 'password', ProfileType.json);
    });

    test('should change the state when user logs out', () async {
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

  // test the method isOwner
  group('isOwner', () {
    test('should return true if the user is the owner of the drive', () async {
      // arrange
      final user = User(
        password: 'password',
        wallet: wallet,
        walletAddress: 'walletAddress',
        walletBalance: BigInt.one,
        cipherKey: SecretKey([]),
        profileType: ProfileType.json,
      );

      // set user
      when(() => mockUserRepository.hasUser()).thenAnswer((_) async => true);

      when(() => mockUserRepository.getUser('password'))
          .thenAnswer((invocation) async => user);

      await arDriveAuth.unlockUser(password: 'password');

      // act
      final result = arDriveAuth.isOwner('walletAddress');

      // assert
      expect(result, true);
    });

    test('should return false if the user is not logged in', () async {
      // act
      final result = arDriveAuth.isOwner('walletAddress');

      // assert
      expect(result, false);
    });

    test(
        'should return false if the user is logged in but the wallet address is different',
        () async {
      // arrange
      final user = User(
        password: 'password',
        wallet: wallet,
        walletAddress: 'walletAddress',
        walletBalance: BigInt.one,
        cipherKey: SecretKey([]),
        profileType: ProfileType.json,
      );

      // set user
      when(() => mockUserRepository.hasUser()).thenAnswer((_) async => true);

      when(() => mockUserRepository.getUser('password'))
          .thenAnswer((invocation) async => user);

      await arDriveAuth.unlockUser(password: 'password');

      // act

      final result = arDriveAuth.isOwner('walletAddress2');

      // assert
      expect(result, false);
    });
  });
}

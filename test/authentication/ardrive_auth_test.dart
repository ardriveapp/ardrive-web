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

  final wallet = getTestWallet();

  setUp(() {
    mockArweaveService = MockArweaveService();
    mockUserRepository = MockUserRepository();
    mockArDriveCrypto = MockArDriveCrypto();

    arDriveAuth = ArDriveAuth(
      arweave: mockArweaveService,
      userRepository: mockUserRepository,
      crypto: mockArDriveCrypto,
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

  group('ArDriveAuth testing login method', () {
    final loggedUser = User(
      password: 'password',
      wallet: wallet,
      walletAddress: 'walletAddress',
      walletBalance: BigInt.one,
      cipherKey: SecretKey([]),
      profileType: ProfileType.json,
    );
    test('should return the user when has password and login with sucess',
        () async {
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

    test('should return the user when has not password', () async {
      // arrange
      // no private drives
      when(() => mockArweaveService.getFirstPrivateDriveTxId(wallet,
          maxRetries: any(named: 'maxRetries'))).thenAnswer((_) async => null);
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
}

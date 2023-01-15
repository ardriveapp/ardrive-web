import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/user/services/user_service.dart';
import 'package:ardrive/user/user.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';

class MockTransaction extends Mock implements TransactionCommonMixin {}

void main() {
  late UserService userService;
  late ArweaveService mockArweaveService;
  late ProfileDao mockProfileDao;

  const rightPassword = 'right-password';

  final wallet = getTestWallet();

  final listOfTransactions = [MockTransaction()];
  final emptyListOfTranscations = <TransactionCommonMixin>[];

  setUp(() {
    mockArweaveService = MockArweaveService();
    mockProfileDao = MockProfileDao();

    userService = UserService(
      mockProfileDao,
      mockArweaveService,
    );

    // register fallback values
    registerFallbackValue(listOfTransactions);
    registerFallbackValue(emptyListOfTranscations);
  });

  group('testing getProfile method', () {
    test('should return a user with the same information of the profile',
        () async {
      when(() => mockProfileDao.loadDefaultProfile(rightPassword))
          .thenAnswer((_) async => Future.value(ProfileLoadDetails(
              wallet: wallet,
              walletPublicKey: '',
              key: SecretKey([1, 2, 3]),
              details: Profile(
                encryptedPublicKey: Uint8List.fromList([]),
                encryptedWallet: Uint8List.fromList([]),
                keySalt: Uint8List.fromList([]),
                profileType: 0, //json
                username: '',
                walletPublicKey: '',
                id: 'id',
              ))));
      when(() => mockArweaveService.getWalletBalance(any()))
          .thenAnswer((_) async => BigInt.zero);

      final result = await userService.getProfile(rightPassword);
      final userToMatch = User(
        password: rightPassword,
        wallet: wallet,
        walletAddress: await wallet.getAddress(),
        walletBalance: BigInt.zero,
        cipherKey: SecretKey([1, 2, 3]),
        profileType: ProfileType.json,
      );

      expect(result.password, userToMatch.password);
      expect(result.wallet, userToMatch.wallet);
      expect(result.walletAddress, await wallet.getAddress());
      expect(result.walletBalance, userToMatch.walletBalance);
      expect(result.cipherKey, userToMatch.cipherKey);
      expect(result.profileType, userToMatch.profileType);
      verify(() => mockProfileDao.loadDefaultProfile(rightPassword)).called(1);

      // TODO: verify why comparing user object is not working
      // expect(
      //     result,
      //     User(
      //       password: rightPassword,
      //       wallet: wallet,
      //       walletAddress: await wallet.getAddress(),
      //       walletBalance: BigInt.zero,
      //       cipherKey: SecretKey([1, 2, 3]),
      //       profileType: ProfileType.json,
      //     ),
      // );
    });
  });

  group('testing isUserLoggedIn method', () {
    test('should return true if there is a profile', () async {
      when(() => mockProfileDao.getDefaultProfile())
          .thenAnswer((_) async => Future.value(Profile(
                encryptedPublicKey: Uint8List.fromList([]),
                encryptedWallet: Uint8List.fromList([]),
                keySalt: Uint8List.fromList([]),
                profileType: 0, //json
                username: '',
                walletPublicKey: '',
                id: 'id',
              )));

      final result = await userService.isUserLoggedIn();

      expect(result, true);

      verify(() => mockProfileDao.getDefaultProfile()).called(1);
    });

    test('should return false if there is a profile', () async {
      when(() => mockProfileDao.getDefaultProfile())
          .thenAnswer((_) async => Future.value(null));

      final result = await userService.isUserLoggedIn();

      expect(result, false);

      verify(() => mockProfileDao.getDefaultProfile()).called(1);
    });
  });

  group('testing isExistingUser function', () {
    test('should return true if there is a profile', () async {
      when(() => mockArweaveService.getUniqueUserDriveEntityTxs(any(),
              maxRetries: any(named: 'maxRetries')))
          .thenAnswer((invocation) async => listOfTransactions);

      final result = await userService.isExistingUser('wallet_address');

      expect(result, true);

      verify(() => mockArweaveService.getUniqueUserDriveEntityTxs(any(),
          maxRetries: any(named: 'maxRetries'))).called(1);
    });

    test('should return false if there is a profile', () async {
      when(() => mockArweaveService.getUniqueUserDriveEntityTxs(any(),
              maxRetries: any(named: 'maxRetries')))
          .thenAnswer((_) async => emptyListOfTranscations);

      final result = await userService.isExistingUser('wallet_address');

      expect(result, false);

      verify(() => mockArweaveService.getUniqueUserDriveEntityTxs(any(),
          maxRetries: any(named: 'maxRetries'))).called(1);
    });
  });

  group('testing saveUser method', () {
    test('should save the user', () async {
      final user = User(
        password: rightPassword,
        wallet: wallet,
        walletAddress: await wallet.getAddress(),
        walletBalance: BigInt.zero,
        cipherKey: SecretKey([1, 2, 3]),
        profileType: ProfileType.json,
      );

      when(() => mockProfileDao.addProfile(
              'user.username', rightPassword, wallet, user.profileType))
          .thenAnswer((_) async => Future.value(SecretKey([1, 2, 3])));

      await userService.saveUser(
        rightPassword,
        user.profileType,
        user.wallet,
      );

      verify(() => mockProfileDao.addProfile(
          'user.username', rightPassword, wallet, user.profileType)).called(1);
    });
  });

  group('testing deleteUser method', () {
    test('should delete the user', () async {
      when(() => mockProfileDao.deleteProfile())
          .thenAnswer((_) async => Future.value());

      await userService.deleteUser();

      verify(() => mockProfileDao.deleteProfile()).called(1);
    });
  });
}

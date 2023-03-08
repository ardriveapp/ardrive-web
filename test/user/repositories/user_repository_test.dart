import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/user/repositories/user_repository.dart';
import 'package:ardrive/user/user.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';

class MockTransaction extends Mock implements TransactionCommonMixin {}

void main() {
  late UserRepository userRepository;
  late ArweaveService mockArweaveService;
  late ProfileDao mockProfileDao;

  const rightPassword = 'right-password';

  final wallet = getTestWallet();

  final listOfTransactions = [MockTransaction()];
  final emptyListOfTranscations = <TransactionCommonMixin>[];

  setUp(() {
    mockArweaveService = MockArweaveService();
    mockProfileDao = MockProfileDao();

    userRepository = UserRepository(
      mockProfileDao,
      mockArweaveService,
    );

    // register fallback values
    registerFallbackValue(listOfTransactions);
    registerFallbackValue(emptyListOfTranscations);
  });

  group('testing getUser method', () {
    setUp(() {
      when(() => mockProfileDao.getDefaultProfile())
          .thenAnswer((_) async => Profile(
                encryptedPublicKey: Uint8List.fromList([]),
                encryptedWallet: Uint8List.fromList([]),
                keySalt: Uint8List.fromList([]),
                profileType: 0, //json
                username: '',
                walletPublicKey: '',
                id: 'id',
              ));
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
    });

    test('should return a user with the same information of the profile',
        () async {
      final result = await userRepository.getUser(rightPassword);

      final userToMatch = User(
        password: rightPassword,
        wallet: wallet,
        walletAddress: await wallet.getAddress(),
        walletBalance: BigInt.zero,
        cipherKey: SecretKey([1, 2, 3]),
        profileType: ProfileType.json,
      );

      expect(result, isNotNull);
      expect(result!.password, userToMatch.password);
      expect(result.wallet, userToMatch.wallet);
      expect(result.walletAddress, await wallet.getAddress());
      expect(result.walletBalance, userToMatch.walletBalance);
      expect(result.cipherKey, userToMatch.cipherKey);
      expect(result.profileType, userToMatch.profileType);
      verify(() => mockProfileDao.loadDefaultProfile(rightPassword)).called(1);
    });

    test('should return null if there is no profile', () async {
      when(() => mockProfileDao.getDefaultProfile())
          .thenAnswer((_) async => Future.value(null));

      final result = await userRepository.getUser(rightPassword);

      expect(result, isNull);
      verify(() => mockProfileDao.getDefaultProfile()).called(1);
      verifyNever(() => mockProfileDao.loadDefaultProfile(rightPassword));
    });
  });

  group('testing hasUser method', () {
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

      final result = await userRepository.hasUser();

      expect(result, true);

      verify(() => mockProfileDao.getDefaultProfile()).called(1);
    });

    test('should return false if there is a profile', () async {
      when(() => mockProfileDao.getDefaultProfile())
          .thenAnswer((_) async => Future.value(null));

      final result = await userRepository.hasUser();

      expect(result, false);

      verify(() => mockProfileDao.getDefaultProfile()).called(1);
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

      await userRepository.saveUser(
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

      await userRepository.deleteUser();

      verify(() => mockProfileDao.deleteProfile()).called(1);
    });
  });
}

import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/user/repositories/user_repository.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';

class MockTransaction extends Mock implements TransactionCommonMixin {}

class MockArioSDK extends Mock implements ArioSDK {}

void main() {
  late UserRepository userRepository;
  late ArweaveService mockArweaveService;
  late ProfileDao mockProfileDao;
  late MockArioSDK mockArioSDK;

  const rightPassword = 'right-password';

  final wallet = getTestWallet();

  final listOfTransactions = [MockTransaction()];
  final emptyListOfTranscations = <TransactionCommonMixin>[];

  setUp(() {
    mockArweaveService = MockArweaveService();
    mockProfileDao = MockProfileDao();
    mockArioSDK = MockArioSDK();

    userRepository = UserRepository(
      mockProfileDao,
      mockArweaveService,
      mockArioSDK,
    );

    // register fallback values
    registerFallbackValue(listOfTransactions);
    registerFallbackValue(emptyListOfTranscations);
  });

  group('UserRepository class', () {
    group('getUser method', () {
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
          errorFetchingIOTokens: false,
        );

        expect(result, isNotNull);
        expect(result!.password, userToMatch.password);
        expect(result.wallet, userToMatch.wallet);
        expect(result.walletAddress, await wallet.getAddress());
        expect(result.walletBalance, userToMatch.walletBalance);
        expect(result.cipherKey, userToMatch.cipherKey);
        expect(result.profileType, userToMatch.profileType);
        verify(() => mockProfileDao.loadDefaultProfile(rightPassword))
            .called(1);
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

    group('hasUser method', () {
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

    group('saveUser method', () {
      test('should save the user', () async {
        final user = User(
          password: rightPassword,
          wallet: wallet,
          walletAddress: await wallet.getAddress(),
          walletBalance: BigInt.zero,
          cipherKey: SecretKey([1, 2, 3]),
          profileType: ProfileType.json,
          errorFetchingIOTokens: false,
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
                'user.username', rightPassword, wallet, user.profileType))
            .called(1);
      });
    });

    group('deleteUser method', () {
      test('should delete the user when has user', () async {
        when(() => mockProfileDao.deleteProfile())
            .thenAnswer((_) async => Future.value());
        when(() => mockProfileDao.getDefaultProfile()).thenAnswer(
          (_) async => Future.value(
            Profile(
              encryptedPublicKey: Uint8List.fromList([]),
              encryptedWallet: Uint8List.fromList([]),
              keySalt: Uint8List.fromList([]),
              profileType: 0, //json
              username: '',
              walletPublicKey: '',
              id: 'id',
            ),
          ),
        );

        await userRepository.deleteUser();

        verify(() => mockProfileDao.getDefaultProfile()).called(1);
        verify(() => mockProfileDao.deleteProfile()).called(1);
      });

      test('should do nothing when there is no user ', () async {
        when(() => mockProfileDao.deleteProfile())
            .thenAnswer((_) async => Future.value());
        when(() => mockProfileDao.getDefaultProfile())
            .thenAnswer((_) async => Future.value(null));

        await userRepository.deleteUser();

        verifyNever(() => mockProfileDao.deleteProfile());
      });
    });

    group('getOwnerOfDefaultProfile method', () {
      test('should return the walletPublicKey when there is a profile',
          () async {
        when(() => mockProfileDao.getDefaultProfile()).thenAnswer(
          (_) async => Future.value(
            Profile(
              encryptedPublicKey: Uint8List.fromList([]),
              encryptedWallet: Uint8List.fromList([]),
              keySalt: Uint8List.fromList([]),
              profileType: 0, //json
              username: '',
              walletPublicKey: 'walletPublicKey',
              id: 'id',
            ),
          ),
        );

        final result = await userRepository.getOwnerOfDefaultProfile();

        expect(result, 'walletPublicKey');
        verify(() => mockProfileDao.getDefaultProfile()).called(1);
      });

      test('should return null when there is no profile', () async {
        when(() => mockProfileDao.getDefaultProfile())
            .thenAnswer((_) async => Future.value(null));

        final result = await userRepository.getOwnerOfDefaultProfile();

        expect(result, null);
        verify(() => mockProfileDao.getDefaultProfile()).called(1);
      });
    });

    group('getIOTokens method', () {
      test('should return IO tokens when ArioSDK is supported', () async {
        final wallet = getTestWallet();
        const expectedIOTokens = '100';
        final walletAddress = await wallet.getAddress();

        AppPlatform.setMockPlatform(platform: SystemPlatform.Web);

        when(() => mockArioSDK.getARIOTokens(walletAddress))
            .thenAnswer((_) async => expectedIOTokens);

        final result = await userRepository.getARIOTokens(wallet);

        expect(result, expectedIOTokens);
        verify(() => mockArioSDK.getARIOTokens(walletAddress)).called(1);
      });

      test('should return null when ArioSDK is not supported', () async {
        final wallet = getTestWallet();

        AppPlatform.setMockPlatform(platform: SystemPlatform.Android);

        final result = await userRepository.getARIOTokens(wallet);

        expect(result, isNull);

        verifyNever(() => mockArioSDK.getARIOTokens(any()));
      });

      test('should return null when ArioSDK is not supported', () async {
        final wallet = getTestWallet();

        AppPlatform.setMockPlatform(platform: SystemPlatform.iOS);

        final result = await userRepository.getARIOTokens(wallet);

        expect(result, isNull);

        verifyNever(() => mockArioSDK.getARIOTokens(any()));
      });
    });

    group('getBalance method', () {
      test('should return the correct balance', () async {
        final wallet = getTestWallet();
        final expectedBalance = BigInt.from(100);
        final walletAddress = await wallet.getAddress();

        when(() => mockArweaveService.getWalletBalance(walletAddress))
            .thenAnswer((_) async => expectedBalance);
        when(() => mockArweaveService.getPendingTxFees(walletAddress))
            .thenAnswer((_) async => BigInt.from(0));

        final result = await userRepository.getBalance(wallet);

        expect(result, expectedBalance);
        verify(() => mockArweaveService.getWalletBalance(walletAddress))
            .called(1);
        verify(() => mockArweaveService.getPendingTxFees(walletAddress))
            .called(1);
      });

      test('should return the correct balance when has pending transactions',
          () async {
        final wallet = getTestWallet();
        final expectedBalance = BigInt.from(100);
        final expectedPendingTxFees = BigInt.from(10);
        final walletAddress = await wallet.getAddress();

        when(() => mockArweaveService.getWalletBalance(walletAddress))
            .thenAnswer((_) async => expectedBalance);
        when(() => mockArweaveService.getPendingTxFees(walletAddress))
            .thenAnswer((_) async => expectedPendingTxFees);

        final result = await userRepository.getBalance(wallet);

        expect(result, expectedBalance - expectedPendingTxFees);
        verify(() => mockArweaveService.getWalletBalance(walletAddress))
            .called(1);
        verify(() => mockArweaveService.getPendingTxFees(walletAddress))
            .called(1);
      });
    });
  });
}

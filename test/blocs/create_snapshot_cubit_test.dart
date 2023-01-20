import 'package:ardrive/blocs/create_snapshot/create_snapshot_cubit.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/entities/snapshot_entity.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../test_utils/utils.dart';

Future<Transaction> fakePrepareTransaction(invocation) async {
  final entity = invocation.positionalArguments[0] as SnapshotEntity;
  final wallet = invocation.positionalArguments[1] as Wallet;

  final transaction = await entity.asTransaction();
  transaction.setOwner(await wallet.getOwner());
  transaction.setReward(BigInt.from(100));
  transaction.setLastTx(encodeStringToBase64('lastTx'));

  await transaction.prepareChunks();

  await transaction.sign(wallet);

  return transaction;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CreateSnapshotCubit class', () {
    final arweave = MockArweaveService();
    final profileCubit = MockProfileCubit();
    final driveDao = MockDriveDao();
    final testWallet = getTestWallet();

    setUpAll(() async {
      registerFallbackValue(SnapshotEntity());
      registerFallbackValue(testWallet);
      registerFallbackValue(
        await getTestTransaction('test/fixtures/signed_v2_tx.json'),
      );
      registerFallbackValue(Future.value());
    });

    setUp(() async {
      // mocks the getSegmentedTransactionsFromDrive method of ardrive
      when(
        () => arweave.getSegmentedTransactionsFromDrive(
          any(),
          minBlockHeight: any(named: 'minBlockHeight'),
          maxBlockHeight: any(named: 'maxBlockHeight'),
        ),
      ).thenAnswer(
        (_) => const Stream.empty(),
      );

      // mocks prepareEntityTx method of ardrive
      when(
        () => arweave.prepareEntityTx(
          any(),
          any(),
        ),
      ).thenAnswer(fakePrepareTransaction);

      when(() => arweave.postTx(any())).thenAnswer(
        (_) async => Future<void>.value(),
      );

      // mocks the state of the profile cubit
      when(() => profileCubit.state).thenReturn(
        ProfileLoggedIn(
          username: 'username',
          password: 'password',
          wallet: testWallet,
          walletAddress: await testWallet.getAddress(),
          walletBalance: BigInt.from(100),
          cipherKey: SecretKey([1, 2, 3, 4, 5]),
        ),
      );

      // mocks logoutIfWalletMissmatch
      when(() => profileCubit.logoutIfWalletMismatch()).thenAnswer(
        (_) => Future.value(false),
      );

      when(() => driveDao.writeSnapshotEntity(any())).thenAnswer(
        (_) => Future.value(),
      );

      // mocks PackageInfo
      PackageInfo.setMockInitialValues(
        appName: 'appName',
        packageName: 'packageName',
        version: '1.2.3',
        buildNumber: 'buildNumber',
        buildSignature: 'buildSignature',
      );
    });

    blocTest(
      'has the initial state when just constructed',
      build: () => CreateSnapshotCubit(
        arweave: arweave,
        profileCubit: profileCubit,
        driveDao: driveDao,
      ),
      expect: () => [],
    );

    blocTest(
      'emits the correct states when selectDriveAndHeightRange is called',
      build: () => CreateSnapshotCubit(
        arweave: arweave,
        profileCubit: profileCubit,
        driveDao: driveDao,
      ),
      act: (cubit) => cubit.selectDriveAndHeightRange(
        'driveId',
        Range(start: 0, end: 1),
        100,
      ),
      expect: () => [
        ComputingSnapshotData(
          driveId: 'driveId',
          range: Range(start: 0, end: 1),
        ),
        // can't check for the actual value because it contains a signed transaction
        isA<ConfirmingSnapshotCreation>(),
      ],
    );

    blocTest(
      'emits the correct states when confirmSnapshotCreation is called',
      build: () => CreateSnapshotCubit(
        arweave: arweave,
        profileCubit: profileCubit,
        driveDao: driveDao,
      ),
      act: (cubit) => cubit
          .selectDriveAndHeightRange(
            'driveId',
            Range(start: 0, end: 1),
            100,
          )
          .then((value) => cubit.confirmSnapshotCreation()),
      expect: () => [
        ComputingSnapshotData(
          driveId: 'driveId',
          range: Range(start: 0, end: 1),
        ),
        // can't check for the actual value because it contains a signed transaction
        isA<ConfirmingSnapshotCreation>(),
        UploadingSnapshot(),
        SnapshotUploadSuccess(),
      ],
    );
  });
}

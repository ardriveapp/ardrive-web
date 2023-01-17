import 'package:ardrive/blocs/create_snapshot/create_snapshot_cubit.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/entities/snapshot_entity.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../test_utils/utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CreateSnapshotCubit class', () {
    final arweave = MockArweaveService();
    final profileCubit = MockProfileCubit();
    final driveDao = MockDriveDao();
    final testWallet = getTestWallet();

    setUpAll(() {
      registerFallbackValue(SnapshotEntity());
      registerFallbackValue(testWallet);
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
      ).thenAnswer(
        (invocation) async =>
            await invocation.positionalArguments[0].asTransaction(),
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
        tempFile: './temp.bin',
        arweave: arweave,
        profileCubit: profileCubit,
        driveDao: driveDao,
      ),
      expect: () => [],
    );

    blocTest(
      'emits the correct states when selectDriveAndHeightRange is called',
      build: () => CreateSnapshotCubit(
        tempFile: './temp.bin',
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
      ],
    );

    blocTest(
      'emits the correct states when upload is called',
      build: () => CreateSnapshotCubit(
        tempFile: './temp.bin',
        arweave: arweave,
        profileCubit: profileCubit,
        driveDao: driveDao,
      ),
      act: (cubit) => cubit.upload(),
      expect: () => [
        Uploading(),
      ],
    );
  });
}

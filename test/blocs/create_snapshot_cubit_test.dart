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

  group(
    'CreateSnapshotCubit class',
    () {
      final arweave = MockArweaveService();
      final profileCubit = MockProfileCubit();
      final driveDao = MockDriveDao();
      final pst = MockPstService();
      final tabVisibility = MockTabVisibilitySingleton();
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
          (_) async* {
            await Future.delayed(const Duration(milliseconds: 1));
          },
        );

        // mocks prepareEntityTx method of ardrive
        when(
          () => arweave.prepareEntityTx(
            any(),
            any(),
            any(),
            skipSignature: any(named: 'skipSignature'),
          ),
        ).thenAnswer(fakePrepareTransaction);

        when(() => arweave.postTx(any())).thenAnswer(
          (_) async => Future<void>.value(),
        );

        when(() => arweave.getArUsdConversionRate()).thenAnswer(
          (_) => Future<double>.value(1),
        );

        when(() => arweave.getCurrentBlockHeight()).thenAnswer(
          (_) => Future<int>.value(100),
        );

        // mocks the state of the profile cubit
        when(() => profileCubit.state).thenReturn(
          ProfileLoggedIn(
            username: 'username',
            password: 'password',
            wallet: testWallet,
            walletAddress: await testWallet.getAddress(),
            walletBalance: BigInt.from(100),
            cipherKey: SecretKey(
              [1, 2, 3, 4, 5],
            ),
            useTurbo: false,
          ),
        );

        // mocks logoutIfWalletMissmatch
        when(() => profileCubit.logoutIfWalletMismatch()).thenAnswer(
          (_) => Future.value(false),
        );

        // mocks the isCurrentProfileArConnect method
        when(() => profileCubit.isCurrentProfileArConnect()).thenAnswer(
          (_) => Future.value(false),
        );

        when(() => pst.addCommunityTipToTx(any())).thenAnswer(
          (_) => Future<double>.value(0.1),
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
          tabVisibility: tabVisibility,
          pst: pst,
        ),
        expect: () => [],
      );

      blocTest(
        'emits the correct states when confirmDriveAndHeighRange is called',
        build: () => CreateSnapshotCubit(
          arweave: arweave,
          profileCubit: profileCubit,
          driveDao: driveDao,
          tabVisibility: tabVisibility,
          pst: pst,
        ),
        act: (cubit) => cubit.confirmDriveAndHeighRange(
          'driveId',
          range: Range(start: 0, end: 1),
        ),
        expect: () => [
          ComputingSnapshotData(
            driveId: 'driveId',
            range: Range(start: 0, end: 1),
          ),
          PreparingAndSigningTransaction(isArConnectProfile: false),
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
          tabVisibility: tabVisibility,
          pst: pst,
        ),
        act: (cubit) => cubit
            .confirmDriveAndHeighRange(
              'driveId',
              range: Range(start: 0, end: 1),
            )
            .then((value) => cubit.confirmSnapshotCreation()),
        expect: () => [
          ComputingSnapshotData(
            driveId: 'driveId',
            range: Range(start: 0, end: 1),
          ),
          PreparingAndSigningTransaction(isArConnectProfile: false),
          // can't check for the actual value because it contains a signed transaction
          isA<ConfirmingSnapshotCreation>(),
          UploadingSnapshot(),
          SnapshotUploadSuccess(),
        ],
      );

      blocTest(
        'emits failure when network error',
        build: () => CreateSnapshotCubit(
          arweave: arweave,
          profileCubit: profileCubit,
          driveDao: driveDao,
          tabVisibility: tabVisibility,
          pst: pst,
          throwOnDataComputingForTesting: true,
        ),
        act: (cubit) => cubit.confirmDriveAndHeighRange(
          'driveId',
          range: Range(start: 0, end: 1),
        ),
        expect: () => [
          ComputingSnapshotData(
            driveId: 'driveId',
            range: Range(start: 0, end: 1),
          ),
          isA<ComputeSnapshotDataFailure>(),
        ],
      );

      blocTest(
        'the range to be snapshotted is limited to 15 blocks before the current block height when exceeded',
        build: () => CreateSnapshotCubit(
          arweave: arweave,
          profileCubit: profileCubit,
          driveDao: driveDao,
          tabVisibility: tabVisibility,
          pst: pst,
        ),
        act: (cubit) => cubit.confirmDriveAndHeighRange(
          'driveId',
          range: Range(start: 0, end: 101),
        ),
        expect: () => [
          ComputingSnapshotData(
            driveId: 'driveId',
            range: Range(start: 0, end: 85),
          ),
          PreparingAndSigningTransaction(isArConnectProfile: false),
          isA<ConfirmingSnapshotCreation>(),
        ],
      );

      blocTest(
        'emits failure on insufficient balance',
        build: () => CreateSnapshotCubit(
          arweave: arweave,
          profileCubit: profileCubit,
          driveDao: driveDao,
          tabVisibility: tabVisibility,
          pst: pst,
          throwOnDataComputingForTesting: true,
        ),
        act: (cubit) => cubit.confirmDriveAndHeighRange(
          'driveId',
          range: Range(start: 0, end: 1),
        ),
        expect: () => [
          ComputingSnapshotData(
            driveId: 'driveId',
            range: Range(start: 0, end: 1),
          ),
          isA<ComputeSnapshotDataFailure>(),
        ],
      );

      blocTest(
        'stops the stream on cancelSnapshotCreation',
        build: () => CreateSnapshotCubit(
          arweave: arweave,
          profileCubit: profileCubit,
          driveDao: driveDao,
          tabVisibility: tabVisibility,
          pst: pst,
        ),
        act: (cubit) async {
          await Future.wait([
            cubit.confirmDriveAndHeighRange(
              'driveId',
              range: Range(start: 0, end: 1),
            ),
            Future.delayed(
              const Duration(microseconds: 1),
              () {
                cubit.cancelSnapshotCreation();
              },
            )
          ]);
        },
        expect: () => [
          ComputingSnapshotData(
            driveId: 'driveId',
            range: Range(start: 0, end: 1),
          ),
          CreateSnapshotInitial(),
        ],
      );

      group('CreateSnapshotCubit - ArConnect', () {
        setUp(() {
          // mocks the isCurrentProfileArConnect method
          when(() => profileCubit.isCurrentProfileArConnect()).thenAnswer(
            (_) => Future.value(true),
          );

          // mocks arweave service: throws 1st time, suceed the next ones
          final prepareEntityTxResponses = [
            (_) => throw Exception('Fake error on prepare entity tx'),
            (invocation) => fakePrepareTransaction(invocation)
          ];
          when(
            () => arweave.prepareEntityTx(
              any(),
              any(),
              any(),
              skipSignature: any(named: 'skipSignature'),
            ),
          ).thenAnswer(
            (invocation) async {
              return await prepareEntityTxResponses.removeAt(0)(invocation);
            },
          );

          // mocks the TabVisibilitySingleton class
          final responses = [false, false, true];
          when(() => tabVisibility.isTabFocused()).thenAnswer(
            (_) => responses.removeAt(0),
          );

          when(() => tabVisibility.onTabGetsFocusedFuture(any())).thenAnswer(
            (invocation) async {
              await Future.delayed(const Duration(milliseconds: 10));
              await invocation.positionalArguments.first();
            },
          );
        });

        blocTest(
          'waits for the tab to be focused again on prepareTx',
          build: () => CreateSnapshotCubit(
            arweave: arweave,
            profileCubit: profileCubit,
            driveDao: driveDao,
            tabVisibility: tabVisibility,
            pst: pst,
            throwOnPrepareTxForTesting: true,
          ),
          act: (cubit) async {
            Future.delayed(const Duration(milliseconds: 8))
                .then((_) => cubit.throwOnPrepareTxForTesting = false);
            await cubit.confirmDriveAndHeighRange(
              'driveId',
              range: Range(start: 0, end: 1),
            );
          },
          expect: () => [
            ComputingSnapshotData(
              driveId: 'driveId',
              range: Range(start: 0, end: 1),
            ),
            PreparingAndSigningTransaction(isArConnectProfile: true),
            isA<ConfirmingSnapshotCreation>(),
          ],
        );

        blocTest(
          'waits for the tab to be focused again on signTx',
          build: () => CreateSnapshotCubit(
            arweave: arweave,
            profileCubit: profileCubit,
            driveDao: driveDao,
            tabVisibility: tabVisibility,
            pst: pst,
            throwOnSignTxForTesting: true,
          ),
          act: (cubit) async {
            Future.delayed(const Duration(milliseconds: 8)).then((_) {
              cubit.throwOnSignTxForTesting = false;
              cubit.returnWithoutSigningForTesting = true;
            });
            await cubit.confirmDriveAndHeighRange(
              'driveId',
              range: Range(start: 0, end: 1),
            );
          },
        );
      });
    },
  );
}

import 'package:ardrive/blocs/create_snapshot/create_snapshot_cubit.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/entities/snapshot_entity.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/services/arconnect/arconnect_prompt.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/turbo/models/turbo_free_allowance.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../test_utils/utils.dart';
import '../turbo/turbo_test.dart';

Future<Transaction> fakePrepareTransaction(invocation) async {
  final entity = invocation.positionalArguments[0] as SnapshotEntity;
  final wallet = invocation.positionalArguments[1] as Wallet;

  final transaction = await entity.asTransaction();
  transaction.setOwner(await wallet.getOwner());
  transaction.setReward(BigInt.from(100));
  transaction.setLastTx(encodeStringToBase64('lastTx'));

  await transaction.prepareChunks();

  await transaction.sign(ArweaveSigner(wallet));

  return transaction;
}

Future<DataItem> fakePrepareDataItem(invocation) async {
  final entity = invocation.positionalArguments[0] as SnapshotEntity;
  final wallet = invocation.positionalArguments[1] as Wallet;

  final dataItem = await entity.asDataItem(null);
  dataItem.setOwner(await wallet.getOwner());

  await dataItem.sign(ArweaveSigner(wallet));

  return dataItem;
}

class MockAppConfig extends Mock implements AppConfig {}

class MockTurboUploadService extends Mock implements TurboUploadService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
    'CreateSnapshotCubit class',
    () {
      final arweave = MockArweaveService();
      final profileCubit = MockProfileCubit();
      late DriveDao driveDao;
      late Database db;
      late DriveID driveId;
      final pst = MockPstService();
      final tabVisibility = MockTabVisibilitySingleton();
      final testWallet = getTestWallet();
      final configService = MockConfigService();
      final appConfig = MockAppConfig();
      final auth = MockArDriveAuth();
      final paymentService = MockPaymentService();
      final turboBalanceRetriever = MockTurboBalanceRetriever();
      final turboService = MockTurboUploadService();

      setUpAll(() async {
        registerFallbackValue(SnapshotEntity());
        registerFallbackValue(testWallet);
        registerFallbackValue(
          await getTestTransaction('test/fixtures/signed_v2_tx.json'),
        );
        registerFallbackValue(
          await getTestDataItem('test/fixtures/signed_v2_tx.json'),
        );
        registerFallbackValue(Future.value());

        db = getTestDb();
        driveDao = db.driveDao;
      });

      setUp(() async {
        registerFallbackValue(BigInt.one);

        final drive = await driveDao.createDrive(
          name: "Mati's drive",
          ownerAddress: await testWallet.getAddress(),
          privacy: 'public',
          wallet: testWallet,
          password: '123',
          profileKey: SecretKey([1, 2, 3, 4, 5]),
          signatureType: '1',
        );
        driveId = drive.driveId;

        when(
          () => arweave.getSegmentedTransactionsFromDrive(
            any(),
            minBlockHeight: any(named: 'minBlockHeight'),
            maxBlockHeight: any(named: 'maxBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
          ),
        ).thenAnswer(
          (_) async* {
            await Future.delayed(const Duration(milliseconds: 1));
          },
        );

        when(() => arweave.getOwnerForDriveEntityWithId(any())).thenAnswer(
          (invocation) => Future.value('owner'),
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

        when(() => arweave.prepareEntityDataItem(
              any(),
              any(),
              skipSignature: any(named: 'skipSignature'),
            )).thenAnswer(fakePrepareDataItem);

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
            user: User(
              password: 'password',
              wallet: testWallet,
              walletAddress: await testWallet.getAddress(),
              walletBalance: BigInt.from(100),
              cipherKey: SecretKey(
                [1, 2, 3, 4, 5],
              ),
              profileType: ProfileType.json,
              ioTokens: 'ioTokens',
              errorFetchingIOTokens: false,
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

        const double stubArToUsdFactor = 10;
        when(() => arweave.getArUsdConversionRateOrNull()).thenAnswer(
          (_) => Future.value(stubArToUsdFactor),
        );

        when(() => arweave.getPrice(byteSize: any(named: 'byteSize')))
            .thenAnswer((invocation) async => BigInt.one);

        when(() => pst.getPSTFee(any()))
            .thenAnswer((invocation) async => Winston(BigInt.one));

        when(() => paymentService.getPriceForBytes(
                byteSize: any(named: 'byteSize')))
            .thenAnswer((invocation) async => BigInt.one);

        when(() => paymentService.getPriceForFiat(
              wallet: null,
              amount: any(named: 'amount'),
              currency: any(named: 'currency'),
            )).thenAnswer((invocation) async => PriceForFiat.zero());

        when(() => turboBalanceRetriever.getBalance(any()))
            .thenAnswer((invocation) async => BigInt.one);

        /// Free allowance covers everything unless a test overrides it, so
        /// these cases exercise the size-based free logic in isolation.
        when(() => turboBalanceRetriever.getFreeAllowance(any()))
            .thenAnswer((_) async => const TurboFreeAllowance.unlimited());

        final MockWallet wallet = MockWallet();
        const address = 'addr';
        final cipher = SecretKey([1, 2, 3, 4, 5]);

        when(() => auth.currentUser).thenAnswer((invocation) => User(
              password: 'password',
              wallet: wallet,
              walletAddress: address,
              walletBalance: BigInt.one,
              cipherKey: cipher,
              profileType: ProfileType.json,
              errorFetchingIOTokens: false,
            ));

        when(() => appConfig.allowedDataItemSizeForTurbo)
            .thenAnswer((invocation) => 100);
        when(() => appConfig.useTurboUpload).thenAnswer((invocation) => true);
        when(() => configService.config).thenAnswer((invocation) => appConfig);

        when(() => tabVisibility.isTabFocused())
            .thenAnswer((invocation) => true);

        when(
          () => turboService.postDataItem(
            dataItem: any(named: 'dataItem'),
            wallet: any(named: 'wallet'),
          ),
        ).thenAnswer((invocation) => Future.value(null));

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
          auth: auth,
          configService: configService,
          paymentService: paymentService,
          turboBalanceRetriever: turboBalanceRetriever,
          turboService: turboService,
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
          auth: auth,
          configService: configService,
          paymentService: paymentService,
          turboBalanceRetriever: turboBalanceRetriever,
          turboService: turboService,
        ),
        act: (cubit) => cubit.confirmDriveAndHeighRange(
          driveId,
          range: Range(start: 0, end: 1),
        ),
        expect: () => [
          ComputingSnapshotData(
            driveId: driveId,
            range: Range(start: 0, end: 1),
          ),
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
          auth: auth,
          configService: configService,
          paymentService: paymentService,
          turboBalanceRetriever: turboBalanceRetriever,
          turboService: turboService,
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
          isA<ConfirmingSnapshotCreation>(),
          PreparingAndSigningTransaction(isArConnectProfile: false),
          UploadingSnapshot(),
          SnapshotUploadSuccess(),
        ],
      );

      group('the wallet check before confirming', () {
        CreateSnapshotCubit build({bool throwOnSign = false}) =>
            CreateSnapshotCubit(
              arweave: arweave,
              profileCubit: profileCubit,
              driveDao: driveDao,
              tabVisibility: tabVisibility,
              pst: pst,
              auth: auth,
              configService: configService,
              paymentService: paymentService,
              turboBalanceRetriever: turboBalanceRetriever,
              turboService: turboService,
              throwOnSignTxForTesting: throwOnSign,
            );

        Future<void> confirm(CreateSnapshotCubit cubit) async {
          await cubit.confirmDriveAndHeighRange(
            'driveId',
            range: Range(start: 0, end: 1),
          );
          // Only what confirming does counts.
          clearInteractions(arweave);
          await cubit.confirmSnapshotCreation();
        }

        void nothingWasPrepared() {
          verifyNever(() => arweave.prepareEntityTx(any(), any(), any(),
              skipSignature: any(named: 'skipSignature')));
          verifyNever(() => arweave.prepareEntityDataItem(any(), any(),
              skipSignature: any(named: 'skipSignature')));
        }

        blocTest<CreateSnapshotCubit, CreateSnapshotState>(
          'on another wallet, fails and prepares nothing',
          setUp: () => when(() => profileCubit.logoutIfWalletMismatch())
              .thenAnswer((_) async => true),
          build: build,
          act: confirm,
          expect: () => [
            isA<ComputingSnapshotData>(),
            isA<ConfirmingSnapshotCreation>(),
            isA<SnapshotUploadFailure>(),
          ],
          verify: (_) => nothingWasPrepared(),
        );

        blocTest<CreateSnapshotCubit, CreateSnapshotState>(
          'Wander unavailable, then Cancel: prepares nothing, the '
          'confirmation stays',
          setUp: () => when(() => profileCubit.logoutIfWalletMismatch())
              .thenThrow(const ArConnectUnavailableException(
                  ArConnectUnavailableReason.noAnswer)),
          build: build,
          act: confirm,
          expect: () => [
            isA<ComputingSnapshotData>(),
            isA<ConfirmingSnapshotCreation>(),
          ],
          verify: (_) => nothingWasPrepared(),
        );

        // A signature that ends in Cancel used to throw past the cubit and
        // leave the loading dialog, which can't be dismissed.
        blocTest<CreateSnapshotCubit, CreateSnapshotState>(
          'a signature that fails ends in a failure, not the spinner',
          build: () => build(throwOnSign: true),
          act: confirm,
          expect: () => [
            isA<ComputingSnapshotData>(),
            isA<ConfirmingSnapshotCreation>(),
            isA<PreparingAndSigningTransaction>(),
            isA<SnapshotUploadFailure>(),
          ],
        );
      });

      blocTest(
        'without a price from Turbo, credits do not pay for it at 0',
        setUp: () {
          when(() => paymentService.getPriceForBytes(
                  byteSize: any(named: 'byteSize')))
              .thenThrow(Exception('Turbo price blocked'));
          // Not free, so the price matters.
          when(() => appConfig.allowedDataItemSizeForTurbo)
              .thenAnswer((invocation) => 0);
        },
        build: () => CreateSnapshotCubit(
          arweave: arweave,
          profileCubit: profileCubit,
          driveDao: driveDao,
          tabVisibility: tabVisibility,
          pst: pst,
          auth: auth,
          configService: configService,
          paymentService: paymentService,
          turboBalanceRetriever: turboBalanceRetriever,
          turboService: turboService,
        ),
        act: (cubit) => cubit
            .confirmDriveAndHeighRange(
              driveId,
              range: Range(start: 0, end: 1),
            )
            .then((_) => cubit.setUploadMethod(UploadMethod.turbo)),
        skip: 1,
        expect: () => [
          isA<ConfirmingSnapshotCreation>()
              .having((s) => s.costEstimateTurbo?.totalCost, 'Turbo cost',
                  BigInt.zero)
              .having((s) => s.sufficientBalanceToPayWithTurbo,
                  'credits cover it', isFalse)
              .having(
                  (s) => s.isTurboUploadPossible, 'Turbo possible', isFalse),
          isA<ConfirmingSnapshotCreation>()
              .having((s) => s.isButtonToUploadEnabled, 'can confirm', isFalse),
        ],
      );

      blocTest(
        'after a top-up, credits still do not pay for it at 0 without a price',
        setUp: () {
          when(() => paymentService.getPriceForBytes(
                  byteSize: any(named: 'byteSize')))
              .thenThrow(Exception('Turbo price blocked'));
          when(() => appConfig.allowedDataItemSizeForTurbo)
              .thenAnswer((invocation) => 0);
        },
        build: () => CreateSnapshotCubit(
          arweave: arweave,
          profileCubit: profileCubit,
          driveDao: driveDao,
          tabVisibility: tabVisibility,
          pst: pst,
          auth: auth,
          configService: configService,
          paymentService: paymentService,
          turboBalanceRetriever: turboBalanceRetriever,
          turboService: turboService,
        ),
        act: (cubit) async {
          await cubit.confirmDriveAndHeighRange(
            driveId,
            range: Range(start: 0, end: 1),
          );
          cubit.setUploadMethod(UploadMethod.turbo);
          await cubit.refreshTurboBalance();
        },
        wait: const Duration(seconds: 3),
        verify: (cubit) {
          final state = cubit.state as ConfirmingSnapshotCreation;
          expect(state.sufficientBalanceToPayWithTurbo, isFalse);
          expect(state.isButtonToUploadEnabled, isFalse);
        },
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
          auth: auth,
          configService: configService,
          paymentService: paymentService,
          turboBalanceRetriever: turboBalanceRetriever,
          turboService: turboService,
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
          auth: auth,
          configService: configService,
          paymentService: paymentService,
          turboBalanceRetriever: turboBalanceRetriever,
          turboService: turboService,
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
          auth: auth,
          configService: configService,
          paymentService: paymentService,
          turboBalanceRetriever: turboBalanceRetriever,
          turboService: turboService,
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
          auth: auth,
          configService: configService,
          paymentService: paymentService,
          turboBalanceRetriever: turboBalanceRetriever,
          turboService: turboService,
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

          when(() => tabVisibility.onTabGetsFocusedFuture(any()))
              .thenAnswer((invocation) {
            final onFocus = invocation.positionalArguments.first;
            return Future.delayed(const Duration(milliseconds: 10)).then(
              (_) => onFocus(),
            );
          });

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
            auth: auth,
            configService: configService,
            paymentService: paymentService,
            turboBalanceRetriever: turboBalanceRetriever,
            turboService: turboService,
          ),
          act: (cubit) async {
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
            auth: auth,
            configService: configService,
            paymentService: paymentService,
            turboBalanceRetriever: turboBalanceRetriever,
            turboService: turboService,
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

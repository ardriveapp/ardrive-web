import 'dart:io';
import 'dart:typed_data';

import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/create_manifest/create_manifest_cubit.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/upload/models/upload_file.dart';
import 'package:ardrive/blocs/upload/models/upload_plan.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/blocs/upload/upload_file_checker.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/core/upload/domain/repository/upload_repository.dart';
import 'package:ardrive/core/upload/uploader.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/manifest/domain/manifest_repository.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/services/config/selected_gateway.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/upload_plan_utils.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pst/pst.dart';

import '../core/upload/uploader_test.dart';
import '../test_utils/utils.dart';
import 'drives_cubit_test.dart';

class MockPstService extends Mock implements PstService {}

class MockUploadPlanUtils extends Mock implements UploadPlanUtils {}

class MockUploadFileSizeChecker extends Mock implements UploadFileSizeChecker {}

class MockTurboUploadService extends Mock implements TurboUploadService {}

class MockArDriveAuth extends Mock implements ArDriveAuth {}

class MockUploadCostEstimateCalculatorForAR extends Mock
    implements UploadCostEstimateCalculatorForAR {}

class MockTurboBalanceRetriever extends Mock implements TurboBalanceRetriever {}

class MockTurboUploadCostCalculator extends Mock
    implements TurboUploadCostCalculator {}

class MockUploadRepository extends Mock implements UploadRepository {}

class MockArDriveUploadPreparationManager extends Mock
    implements ArDriveUploadPreparationManager {}

class MockArnsRepository extends Mock implements ARNSRepository {}

class MockManifestRepository extends Mock implements ManifestRepository {}

class MockCreateManifestCubit extends Mock implements CreateManifestCubit {}

// TODO(thiagocarvalhodev): Test the case of remove files before download when pass ConflictingFileActions.SKIP.
// TODO: Test startUpload
void main() {
  // Mocks
  late DriveDao mockDriveDao;
  late MockArweaveService mockArweave;
  late MockPstService mockPst;
  late MockUploadPlanUtils mockUploadPlanUtils;
  MockProfileCubit? mockProfileCubit;
  late MockUploadFileSizeChecker mockUploadFileSizeChecker;
  late MockArDriveAuth mockArDriveAuth;
  late MockUploadCostEstimateCalculatorForAR
      mockUploadCostEstimateCalculatorForAR;
  late MockTurboBalanceRetriever mockTurboBalanceRetriever;
  late MockTurboUploadCostCalculator mockTurboUploadCostCalculator;
  late MockArDriveUploadPreparationManager mockArDriveUploadPreparationManager;
  late MockConfigService mockConfigService;
  late MockArnsRepository mockArnsRepository;
  late MockUploadRepository mockUploadRepository;
  late MockManifestRepository mockManifestRepository;
  late MockCreateManifestCubit mockCreateManifestCubit;

  const tDriveId = 'drive_id';
  const tRootFolderId = 'root-folder-id';
  const tRootFolderFileCount = 5;
  final tDefaultDate = DateTime.parse('2022-09-06');

  const tNestedFolderId = 'nested-folder-id';
  const tNestedFolderFileCount = 5;

  const tEmptyNestedFolderIdPrefix = 'empty-nested-folder-id';
  const tEmptyNestedFolderCount = 5;

  late Database db;
  late List<UploadFile> tAllConflictingFiles;
  late List<UploadFile> tSomeConflictingFiles;
  late List<UploadFile> tNoConflictingFiles;

  // limits
  const tPrivateFileSizeLimit = 100;

  final tWallet = getTestWallet();
  String? tWalletAddress;

  final tKeyBytes = Uint8List(32);
  fillBytesWithSecureRandom(tKeyBytes);
  mockConfigService = MockConfigService();
  mockManifestRepository = MockManifestRepository();
  mockCreateManifestCubit = MockCreateManifestCubit();

  setUpAll(() async {
    when(() => mockConfigService.config).thenReturn(AppConfig(
      allowedDataItemSizeForTurbo: 1,
      stripePublishableKey: 'stripePublishableKey',
      defaultTurboUploadUrl: 'defaultTurboUploadUrl',
      defaultArweaveGatewayForDataRequest: const SelectedGateway(
        label: 'Arweave.net',
        url: 'https://arweave.net',
      ),
    ));
    when(() => mockManifestRepository.getManifestFilesInFolder(
            driveId: any(named: 'driveId'), folderId: any(named: 'folderId')))
        .thenAnswer((invocation) => Future.value([]));

    registerFallbackValue(SecretKey([]));
    registerFallbackValue(Wallet());
    registerFallbackValue(getFakeUser());
    registerFallbackValue(FolderEntry(
      id: '',
      dateCreated: tDefaultDate,
      driveId: '',
      isGhost: false,
      lastUpdated: tDefaultDate,
      name: '',
      parentFolderId: '',
      isHidden: false,
      path: '',
    ));

    registerFallbackValue(Drive(
        id: '',
        rootFolderId: '',
        name: '',
        ownerAddress: '',
        dateCreated: tDefaultDate,
        lastUpdated: tDefaultDate,
        privacy: '',
        isHidden: false));

    registerFallbackValue(UploadParams(
      user: getFakeUser(),
      files: [],
      targetFolder: getFakeFolder(),
      targetDrive: getFakeDrive(),
      conflictingFiles: {},
      foldersByPath: {},
      containsSupportedImageTypeForThumbnailGeneration: false,
    ));

    tWalletAddress = await tWallet.getAddress();

    db = getTestDb();

    // We need a real file path because in the UploadCubit we needs the size of the file
    // to know if the file is `tooLargeFiles`.
    final tRealPathFile = await IOFile.fromData(
        File('assets/config/dev.json').readAsBytesSync(),
        lastModifiedDate: tDefaultDate,
        name: 'file');

    // The `addTestFilesToDb` will generate files with this path and name, so it
    // will be a confliting file.
    final tConflictingFile = await IOFile.fromData(Uint8List.fromList([1]),
        lastModifiedDate: tDefaultDate, name: '${tRootFolderId}1');

    // Contains only conflicting files.
    tAllConflictingFiles = <UploadFile>[
      UploadFile(ioFile: tConflictingFile, parentFolderId: tRootFolderId)
    ];

    final tDumbTestFile = await IOFile.fromData(Uint8List.fromList([1]),
        name: 'dumb_test_path', lastModifiedDate: tDefaultDate);

    /// This list contains conflicting and non conflicting files.
    tSomeConflictingFiles = <UploadFile>[
      UploadFile(ioFile: tConflictingFile, parentFolderId: tRootFolderId),
      UploadFile(ioFile: tDumbTestFile, parentFolderId: tRootFolderId)
    ];

    tNoConflictingFiles = <UploadFile>[
      UploadFile(ioFile: tRealPathFile, parentFolderId: tRootFolderId)
    ];

    mockArweave = MockArweaveService();
    mockPst = MockPstService();
    mockDriveDao = db.driveDao;
    mockProfileCubit = MockProfileCubit();
    mockUploadPlanUtils = MockUploadPlanUtils();
    mockUploadFileSizeChecker = MockUploadFileSizeChecker();
    mockArDriveAuth = MockArDriveAuth();
    mockUploadCostEstimateCalculatorForAR =
        MockUploadCostEstimateCalculatorForAR();
    mockTurboBalanceRetriever = MockTurboBalanceRetriever();
    mockTurboUploadCostCalculator = MockTurboUploadCostCalculator();
    mockArDriveUploadPreparationManager = MockArDriveUploadPreparationManager();
    mockArnsRepository = MockArnsRepository();
    late MockUploadPlan uploadPlan;
    mockUploadRepository = MockUploadRepository();

    // Setup mock drive.
    await addTestFilesToDb(
      db,
      driveId: tDriveId,
      emptyNestedFolderCount: tEmptyNestedFolderCount,
      emptyNestedFolderIdPrefix: tEmptyNestedFolderIdPrefix,
      rootFolderId: tRootFolderId,
      rootFolderFileCount: tRootFolderFileCount,
      nestedFolderId: tNestedFolderId,
      nestedFolderFileCount: tNestedFolderFileCount,
    );

    final mockUploadCostEstimateAR = UploadCostEstimate(
      totalCost: BigInt.from(100),
      pstFee: BigInt.from(10),
      totalSize: 200,
      usdUploadCost: 25,
    );

    /// total cost 400
    final mockUploadCostEstimateTurbo = UploadCostEstimate(
      totalCost: BigInt.from(400),
      pstFee: BigInt.from(40),
      totalSize: 1000,
      usdUploadCost: 100,
    );

    // mock limit for UploadFileChecker
    when(() => mockUploadFileSizeChecker.hasFileAboveSizeLimit(
        files: any(named: 'files'))).thenAnswer((invocation) async => false);
    const double stubArToUsdFactor = 10;
    when(() => mockArweave.getArUsdConversionRateOrNull()).thenAnswer(
      (_) => Future.value(stubArToUsdFactor),
    );
    uploadPlan = MockUploadPlan();

    when(() => mockArDriveUploadPreparationManager.prepareUpload(
          params: any(named: 'params'),
        )).thenAnswer(
      (invocation) => Future.value(
        UploadPreparation(
          uploadPlansPreparation: UploadPlansPreparation(
            uploadPlanForAr: uploadPlan,
            uploadPlanForTurbo: uploadPlan,
          ),
          uploadPaymentInfo: UploadPaymentInfo(
            defaultPaymentMethod: UploadMethod.ar,
            isUploadEligibleToTurbo: false,
            arCostEstimate: mockUploadCostEstimateAR,
            turboCostEstimate: mockUploadCostEstimateTurbo,
            isFreeUploadPossibleUsingTurbo: false,
            totalSize: 100,
            isTurboAvailable: true,
            turboBalance:
                TurboBalanceInterface(balance: BigInt.from(100), paidBy: []),
          ),
        ),
      ),
    );
  });

  final costEstimate = UploadCostEstimate(
      pstFee: BigInt.one,
      totalCost: BigInt.one,
      totalSize: 100,
      usdUploadCost: 100);

  UploadCubit getUploadCubitInstanceWith(List<UploadFile> files) {
    final cubit = UploadCubit(
      activityTracker: MockActivityTracker(),
      arDriveUploadManager: mockArDriveUploadPreparationManager,
      uploadFileSizeChecker: mockUploadFileSizeChecker,
      driveId: tDriveId,
      parentFolderId: tRootFolderId,
      profileCubit: mockProfileCubit!,
      driveDao: mockDriveDao,
      auth: mockArDriveAuth,
      configService: mockConfigService,
      arnsRepository: mockArnsRepository,
      uploadRepository: mockUploadRepository,
      manifestRepository: mockManifestRepository,
      createManifestCubit: mockCreateManifestCubit,
    );

    cubit.selectFiles(files.map((e) => e.ioFile).toList(), tRootFolderId);
    cubit.isTest = true;
    return cubit;
  }

  void setDumbUploadPlan() => when(() => mockUploadPlanUtils.filesToUploadPlan(
          files: any(named: 'files'),
          cipherKey: any(named: 'cipherKey'),
          wallet: any(named: 'wallet'),
          conflictingFiles: any(named: 'conflictingFiles'),
          targetDrive: any(named: 'targetDrive'),
          targetFolder: any<FolderEntry>(named: 'targetFolder')))
      .thenAnswer((invocation) => Future.value(
            UploadPlan.create(
              useTurbo: false,
              maxDataItemCount: 10,
              fileV2UploadHandles: {},
              fileDataItemUploadHandles: {},
              folderDataItemUploadHandles: {},
              turboUploadService: DontUseUploadService(),
            ),
          ));

  group('check if there are some conflicting file', () {
    setUp(() {
      when(() => mockProfileCubit!.state).thenReturn(
        ProfileLoggedIn(
          user: User(
            password: '123',
            wallet: tWallet,
            walletAddress: tWalletAddress!,
            walletBalance: BigInt.one,
            cipherKey: SecretKey(tKeyBytes),
            profileType: ProfileType.json,
            errorFetchingIOTokens: false,
          ),
          useTurbo: false,
        ),
      );
      when(() => mockProfileCubit!.checkIfWalletMismatch())
          .thenAnswer((i) => Future.value(false));
      when(() => mockProfileCubit!.isCurrentProfileArConnect())
          .thenAnswer((i) => Future.value(false));
      when(() => mockPst.getPSTFee(BigInt.zero))
          .thenAnswer((invocation) => Future.value(Winston(BigInt.zero)));
      when(() => mockUploadCostEstimateCalculatorForAR.calculateCost(
              totalSize: any(named: 'totalSize')))
          .thenAnswer((invocation) => Future.value(costEstimate));

      when(() => mockTurboUploadCostCalculator.calculateCost(
              totalSize: any(named: 'totalSize')))
          .thenAnswer((invocation) => Future.value(costEstimate));
      when(() => mockTurboBalanceRetriever.getBalance(any()))
          .thenAnswer((invocation) => Future.value(BigInt.zero));
      when(() => mockArDriveAuth.currentUser).thenAnswer(
        (_) => User(
          password: 'password',
          wallet: getTestWallet(),
          walletAddress: 'walletAddress',
          walletBalance: BigInt.one,
          cipherKey: SecretKey([]),
          profileType: ProfileType.json,
          errorFetchingIOTokens: false,
        ),
      );

      setDumbUploadPlan();
    });
    blocTest<UploadCubit, UploadState>(
        'should found the conflicting files correctly and set isAllFilesConflicting to true'
        ' when all files are conflicting',
        build: () {
          when(() => mockUploadFileSizeChecker.hasFileAboveWarningSizeLimit(
                  files: any(named: 'files')))
              .thenAnswer((invocation) => Future.value(false));
          when(() => mockArDriveAuth.getWalletAddress())
              .thenAnswer((invocation) => Future.value(tWalletAddress));
          when(() => mockArnsRepository.getAntRecordsForWallet(tWalletAddress!))
              .thenAnswer((invocation) => Future.value([]));
          return getUploadCubitInstanceWith(tAllConflictingFiles);
        },
        act: (cubit) async {
          await cubit.startUploadPreparation();
          await cubit.checkConflictingFiles();
        },
        expect: () => <dynamic>[
              const TypeMatcher<UploadPreparationInitialized>(),
              const TypeMatcher<UploadPreparationInProgress>(),
              UploadFileConflict(
                  areAllFilesConflicting: true,
                  conflictingFileNames: const [
                    '${tRootFolderId}1'
                  ],
                  conflictingFileNamesForFailedFiles: const [
                    '${tRootFolderId}1'
                  ]),
            ]);

    blocTest<UploadCubit, UploadState>(
        'should found the conflicting files correctly and set isAllFilesConflicting to false'
        ' when there is at least one file that is not conflicting',
        build: () {
          return getUploadCubitInstanceWith(tSomeConflictingFiles);
        },
        tearDown: () {},
        act: (cubit) async {
          await cubit.startUploadPreparation();
          await cubit.checkConflictingFiles();
        },
        expect: () => <dynamic>[
              const TypeMatcher<UploadPreparationInitialized>(),
              const TypeMatcher<UploadPreparationInProgress>(),
              UploadFileConflict(
                areAllFilesConflicting: false,
                conflictingFileNames: const ['${tRootFolderId}1'],
                conflictingFileNamesForFailedFiles: const ['${tRootFolderId}1'],
              )
            ]);

    blocTest<UploadCubit, UploadState>(
      'should not found any conflicting file when there isnt any conflicting file to upload',
      build: () {
        return getUploadCubitInstanceWith(tNoConflictingFiles);
      },
      act: (cubit) async {
        await cubit.startUploadPreparation();
        await cubit.checkConflictingFiles();
      },
      expect: () => <dynamic>[
        const TypeMatcher<UploadPreparationInitialized>(),
        const TypeMatcher<UploadPreparationInProgress>(),
        const TypeMatcher<UploadReadyToPrepare>()
      ],
    );
  });

  group(
    'verify if is there any files above the safe limit for public files',
    () {
      setUp(() {
        when(() => mockProfileCubit!.state).thenReturn(
          ProfileLoggedIn(
            useTurbo: false,
            user: User(
              password: '123',
              wallet: tWallet,
              walletAddress: tWalletAddress!,
              walletBalance: BigInt.one,
              cipherKey: SecretKey(tKeyBytes),
              profileType: ProfileType.json,
              errorFetchingIOTokens: false,
            ),
          ),
        );
        when(() => mockProfileCubit!.checkIfWalletMismatch())
            .thenAnswer((i) => Future.value(false));
        when(() => mockPst.getPSTFee(BigInt.zero))
            .thenAnswer((invocation) => Future.value(Winston(BigInt.zero)));
        when(() => mockArweave.getArUsdConversionRate())
            .thenAnswer((invocation) => Future.value(10));
        when(() => mockUploadPlanUtils.filesToUploadPlan(
            files: any(named: 'files'),
            cipherKey: any(named: 'cipherKey'),
            wallet: any(named: 'wallet'),
            conflictingFiles: any(named: 'conflictingFiles'),
            targetDrive: any(named: 'targetDrive'),
            targetFolder: any<FolderEntry>(named: 'targetFolder'))).thenAnswer(
          (invocation) => Future.value(
            UploadPlan.create(
              useTurbo: false,
              maxDataItemCount: 10,
              turboUploadService: DontUseUploadService(),
              fileV2UploadHandles: {},
              fileDataItemUploadHandles: {},
              folderDataItemUploadHandles: {},
            ),
          ),
        );
        when(() => mockProfileCubit!.isCurrentProfileArConnect())
            .thenAnswer((i) => Future.value(true));
      });

      blocTest<UploadCubit, UploadState>(
          'should show the warning when file checker found files above safe limit',
          setUp: () {
            when(() => mockUploadFileSizeChecker.hasFileAboveWarningSizeLimit(
                    files: any(named: 'files')))
                .thenAnswer((invocation) async => true);
          },
          build: () {
            return getUploadCubitInstanceWith(tNoConflictingFiles);
          },
          act: (cubit) async {
            await cubit.startUploadPreparation();
            await cubit.verifyFilesAboveWarningLimit();
          },
          expect: () => <dynamic>[
                const TypeMatcher<UploadPreparationInitialized>(),
                const TypeMatcher<UploadPreparationInProgress>(),
                const TypeMatcher<UploadShowingWarning>()
              ]);
      blocTest<UploadCubit, UploadState>(
          'should show the warning when file checker found files above safe limit and emit UploadReady when user confirm the upload',
          setUp: () {
            when(() => mockUploadFileSizeChecker.hasFileAboveSizeLimit(
                    files: any(named: 'files')))
                .thenAnswer((invocation) async => true);
          },
          build: () {
            return getUploadCubitInstanceWith(tNoConflictingFiles);
          },
          act: (cubit) async {
            await cubit.startUploadPreparation();
            await cubit.verifyFilesAboveWarningLimit();
            await cubit.checkConflictingFiles();
          },
          expect: () => <dynamic>[
                const TypeMatcher<UploadPreparationInitialized>(),
                const TypeMatcher<UploadPreparationInProgress>(),
                const TypeMatcher<UploadShowingWarning>(),
                const TypeMatcher<UploadPreparationInProgress>(),
                const TypeMatcher<UploadPreparationInProgress>(),
                const TypeMatcher<UploadReadyToPrepare>(),
              ]);
      blocTest<UploadCubit, UploadState>(
          'should not show the warning when file checker not found files above safe limit and emit UploadReady without user confirmation',
          setUp: () {
            when(() => mockUploadFileSizeChecker.hasFileAboveSizeLimit(
                    files: any(named: 'files')))
                .thenAnswer((invocation) async => false);
          },
          build: () {
            return getUploadCubitInstanceWith(tNoConflictingFiles);
          },
          act: (cubit) async {
            await cubit.startUploadPreparation();
            await cubit.checkConflictingFiles();
          },
          expect: () => <dynamic>[
                const TypeMatcher<UploadPreparationInitialized>(),
                const TypeMatcher<UploadPreparationInProgress>(),
                const TypeMatcher<UploadPreparationInProgress>(),
                const TypeMatcher<UploadReadyToPrepare>(),
              ]);
    },
  );

  group('prepare upload plan and costs estimates', () {
    setUp(() {
      when(() => mockProfileCubit!.state).thenReturn(
        ProfileLoggedIn(
          user: User(
            password: '123',
            wallet: tWallet,
            walletAddress: tWalletAddress!,
            walletBalance: BigInt.one,
            cipherKey: SecretKey(tKeyBytes),
            profileType: ProfileType.json,
            errorFetchingIOTokens: false,
          ),
          useTurbo: false,
        ),
      );
      when(() => mockProfileCubit!.checkIfWalletMismatch())
          .thenAnswer((i) => Future.value(false));
      when(() => mockPst.getPSTFee(BigInt.zero))
          .thenAnswer((invocation) => Future.value(Winston(BigInt.zero)));
      when(() => mockArweave.getArUsdConversionRate())
          .thenAnswer((invocation) => Future.value(10));
      when(() => mockUploadPlanUtils.filesToUploadPlan(
          files: any(named: 'files'),
          cipherKey: any(named: 'cipherKey'),
          wallet: any(named: 'wallet'),
          conflictingFiles: any(named: 'conflictingFiles'),
          targetDrive: any(named: 'targetDrive'),
          targetFolder: any<FolderEntry>(named: 'targetFolder'))).thenAnswer(
        (invocation) => Future.value(
          UploadPlan.create(
            useTurbo: false,
            maxDataItemCount: 10,
            fileV2UploadHandles: {},
            fileDataItemUploadHandles: {},
            folderDataItemUploadHandles: {},
            turboUploadService: DontUseUploadService(),
          ),
        ),
      );
      when(() => mockProfileCubit!.isCurrentProfileArConnect())
          .thenAnswer((i) => Future.value(true));
    });

    blocTest<UploadCubit, UploadState>(
      'should set the isArconnect to true when user is ArConnect '
      'and prepare the upload and set it to ready',
      build: () {
        return getUploadCubitInstanceWith(tNoConflictingFiles);
      },
      act: (cubit) async {
        await cubit.startUploadPreparation();
        await cubit.prepareUploadPlanAndCostEstimates();
      },
      expect: () => <dynamic>[
        UploadPreparationInitialized(),
        UploadPreparationInProgress(isArConnect: true),
        const TypeMatcher<UploadReadyToPrepare>()
      ],
    );
    blocTest<UploadCubit, UploadState>(
      'should set the isArconnect to false when user isnt ArConnect '
      'and prepare the upload and set it to ready',
      setUp: () {
        when(() => mockProfileCubit!.isCurrentProfileArConnect())
            .thenAnswer((i) => Future.value(false));
      },
      build: () {
        return getUploadCubitInstanceWith(tNoConflictingFiles);
      },
      act: (cubit) async {
        await cubit.startUploadPreparation();
        await cubit.prepareUploadPlanAndCostEstimates();
      },
      expect: () => <dynamic>[
        UploadPreparationInitialized(),
        UploadPreparationInProgress(isArConnect: false),
        const TypeMatcher<UploadReadyToPrepare>()
      ],
    );

    group(
      'file size above limit',
      () {
        late UploadFile tTooLargeFile;
        late List<UploadFile> tTooLargeFiles;

        blocTest<UploadCubit, UploadState>(
          'should emit UploadFileTooLarge with hasFilesToUpload false when we have'
          ' only a file larger than privateFileSizeLimit'
          ' is intended to upload',
          setUp: () async {
            final tFile = File('some_file.txt');
            tFile
                .writeAsBytesSync(Uint8List(tPrivateFileSizeLimit.toInt() + 1));
            tTooLargeFile = UploadFile(
                ioFile: await IOFile.fromData(tFile.readAsBytesSync(),
                    lastModifiedDate: tDefaultDate, name: 'some_file.txt'),
                parentFolderId: tRootFolderId);

            tTooLargeFiles = [tTooLargeFile];
            when(() => mockUploadFileSizeChecker.getFilesAboveSizeLimit(
                    files: any(named: 'files')))
                .thenAnswer((invocation) async => ['some_file.txt']);
          },
          build: () {
            return getUploadCubitInstanceWith(tTooLargeFiles);
          },
          tearDown: () {
            File('some_file.txt').deleteSync();
          },
          act: (cubit) async {
            cubit.isPrivateForTesting = true;
            await cubit.startUploadPreparation();
            await cubit.checkFilesAboveLimit();
          },
          expect: () => <dynamic>[
            UploadPreparationInitialized(),
            UploadFileTooLarge(
                hasFilesToUpload: false,
                tooLargeFileNames: [tTooLargeFiles.first.getIdentifier()],
                isPrivate: false)
          ],
        );

        blocTest<UploadCubit, UploadState>(
          'should emit UploadFileTooLarge with hasFilesToUpload true when we have'
          ' others files not too large to upload',
          setUp: () async {
            final tFile = File('some_file.txt');
            tFile
                .writeAsBytesSync(Uint8List(tPrivateFileSizeLimit.toInt() + 1));
            tTooLargeFile = UploadFile(
                ioFile: await IOFile.fromData(
                    File(tFile.path).readAsBytesSync(),
                    lastModifiedDate: tDefaultDate,
                    name: 'some_file.txt'),
                parentFolderId: tRootFolderId);
            when(() => mockUploadFileSizeChecker.getFilesAboveSizeLimit(
                    files: any(named: 'files')))
                .thenAnswer((invocation) async => ['some_file.txt']);
          },
          build: () {
            final tTooLargeFilesWithNoConflictingFiles = tNoConflictingFiles
              ..add(tTooLargeFile);

            return getUploadCubitInstanceWith(
                tTooLargeFilesWithNoConflictingFiles);
          },
          tearDown: () {
            File('some_file.txt').deleteSync();
          },
          act: (cubit) async {
            cubit.isPrivateForTesting = true;

            await cubit.startUploadPreparation();
            await cubit.checkFilesAboveLimit();
          },
          expect: () => <dynamic>[
            UploadPreparationInitialized(),
            UploadFileTooLarge(
                hasFilesToUpload: false,
                tooLargeFileNames: [tTooLargeFiles.first.getIdentifier()],
                isPrivate: false)
          ],
        );

        blocTest<UploadCubit, UploadState>(
          'should UploadReady when we have a big file under 5GiB and is public and all files are under private size limit',
          setUp: () async {
            final tFile = File('some_file.txt');
            tFile
                .writeAsBytesSync(Uint8List(tPrivateFileSizeLimit.toInt() + 1));
            tTooLargeFile = UploadFile(
                ioFile: await IOFile.fromData(
                    File(tFile.path).readAsBytesSync(),
                    lastModifiedDate: tDefaultDate,
                    name: 'some_file.txt'),
                parentFolderId: tRootFolderId);
          },
          build: () {
            final tTooLargeFilesWithNoConflictingFiles = tNoConflictingFiles
              ..add(tTooLargeFile);

            return getUploadCubitInstanceWith(
                tTooLargeFilesWithNoConflictingFiles);
          },
          tearDown: () {
            File('some_file.txt').deleteSync();
          },
          act: (cubit) async {
            await cubit.startUploadPreparation();
            await cubit.checkFilesAboveLimit();
          },
          expect: () => <dynamic>[
            UploadPreparationInitialized(),
            const TypeMatcher<UploadPreparationInProgress>(),
            const TypeMatcher<UploadPreparationInProgress>(),
            const TypeMatcher<UploadReadyToPrepare>(),
          ],
        );

        blocTest<UploadCubit, UploadState>(
          'should emit UploadReady when we have too large files but at least a not too large'
          ' and skip large files',
          setUp: () async {
            final tFile = File('some_file.txt');

            tFile
                .writeAsBytesSync(Uint8List(tPrivateFileSizeLimit.toInt() + 1));
            tTooLargeFile = UploadFile(
                ioFile: await IOFile.fromData(
                    File(tFile.path).readAsBytesSync(),
                    lastModifiedDate: tDefaultDate,
                    name: 'some_file.txt'),
                parentFolderId: tRootFolderId);
            when(() => mockProfileCubit!.isCurrentProfileArConnect())
                .thenAnswer((i) => Future.value(false));
            when(() => mockUploadFileSizeChecker.getFilesAboveSizeLimit(
                    files: any(named: 'files')))
                .thenAnswer((invocation) async => ['some_file.txt']);
          },
          build: () {
            final tTooLargeFilesWithNoConflictingFiles = tNoConflictingFiles
              ..add(tTooLargeFile);
            final files =
                tNoConflictingFiles + tTooLargeFilesWithNoConflictingFiles;
            return getUploadCubitInstanceWith(files);
          },
          act: (cubit) async {
            cubit.isPrivateForTesting = true;

            await cubit.startUploadPreparation();
            await cubit.checkFilesAboveLimit();
            await cubit.skipLargeFilesAndCheckForConflicts();
          },
          tearDown: () {
            File('some_file.txt').deleteSync();
          },
          expect: () => <dynamic>[
            UploadPreparationInitialized(),
            const TypeMatcher<UploadFileTooLarge>(),
            const TypeMatcher<UploadPreparationInProgress>(),
            const TypeMatcher<UploadReadyToPrepare>(),
          ],
        );
      },
    );

    blocTest<UploadCubit, UploadState>(
      'should emit the upload wallet mismatch state and does nothing',
      setUp: () {
        // wallet mismatch
        when(() => mockProfileCubit!.checkIfWalletMismatch())
            .thenAnswer((i) => Future.value(true));
      },
      build: () {
        return getUploadCubitInstanceWith(tNoConflictingFiles);
      },
      act: (cubit) async {
        await cubit.startUploadPreparation();
        await cubit.prepareUploadPlanAndCostEstimates();
      },
      expect: () =>
          <UploadState>[UploadPreparationInitialized(), UploadWalletMismatch()],
    );
  });
}

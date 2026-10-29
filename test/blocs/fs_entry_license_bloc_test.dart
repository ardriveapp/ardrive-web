import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/upload/models/upload_review_summary.dart';
import 'package:ardrive/core/upload/metadata_write_cost.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
// ignore: depend_on_referenced_packages
import 'package:platform/platform.dart';
import 'package:uuid/uuid.dart';

import '../test_utils/utils.dart';

class _MockCostReader extends Mock implements MetadataWriteCostReader {}

class _FakeItem extends Fake implements ArDriveDataTableItem {}

UploadReviewSummary _summary({
  bool isFree = false,
  bool isCovered = false,
  bool priceUnavailable = false,
}) =>
    UploadReviewSummary(
      method: UploadMethod.turbo,
      isFree: isFree,
      priceUnavailable: priceUnavailable,
      isCovered: isCovered,
      overFreeAllowance: !isFree,
      offersPaymentChoice: false,
      usesLegacySelector: false,
      creditsCost: BigInt.from(40000000),
      creditsBalance: isCovered ? BigInt.from(10).pow(12) : BigInt.zero,
      usdCost: 0.0002,
      arCost: BigInt.zero,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FsEntryLicenseBloc', () {
    late Database db;
    late DriveDao driveDao;
    late ArweaveService arweave;
    late TurboUploadService turboUploadService;
    late ArDriveCrypto crypto;
    late LicenseService licenseService;
    late _MockCostReader costReader;

    late ProfileCubit profileCubit;
    final driveId = const Uuid().v4();
    final rootFolderId = const Uuid().v4();
    final nestedFolderId = const Uuid().v4();
    final conflictTestFolderId = const Uuid().v4();
    const rootFolderFileCount = 3;

    setUp(() async {
      registerFallbackValue(
        await getTestTransaction('test/fixtures/signed_v2_tx.json'),
      );
      registerFallbackValue(
        await getTestDataItem('test/fixtures/signed_v2_tx.json'),
      );
      registerFallbackValue(DataBundle(blob: Uint8List(0)));
      registerFallbackValue(FileEntity());
      registerFallbackValue(Wallet());
      registerFallbackValue(BigInt.zero);
      registerFallbackValue(<int>[]);

      db = getTestDb();
      await db.batch((batch) {
        // Default date
        final defaultDate = DateTime(2017, 9, 7, 17, 30);
        // Create fake drive for test
        batch.insert(
          db.drives,
          DrivesCompanion.insert(
            id: driveId,
            rootFolderId: rootFolderId,
            ownerAddress: 'fake-owner-address',
            name: 'fake-drive-name',
            privacy: DrivePrivacyTag.public,
          ),
        );
        // Create fake root folder for drive and sub folders
        batch.insertAll(db.folderEntries, [
          FolderEntriesCompanion.insert(
            id: rootFolderId,
            driveId: driveId,
            name: 'fake-drive-name',
            isHidden: const Value(false),
            path: '',
          ),
          FolderEntriesCompanion.insert(
            id: nestedFolderId,
            driveId: driveId,
            parentFolderId: Value(rootFolderId),
            name: nestedFolderId,
            isHidden: const Value(false),
            path: '',
          ),
          FolderEntriesCompanion.insert(
            id: conflictTestFolderId,
            driveId: driveId,
            parentFolderId: Value(rootFolderId),
            name: conflictTestFolderId,
            isHidden: const Value(false),
            path: '',
          ),
        ]);
        // Insert fake files
        batch.insertAll(
          db.fileEntries,
          [
            ...List.generate(
              rootFolderFileCount,
              (i) {
                final fileId = '$rootFolderId$i';
                return FileEntriesCompanion.insert(
                  id: fileId,
                  driveId: driveId,
                  parentFolderId: rootFolderId,
                  name: fileId,
                  dataTxId: '${fileId}Data',
                  size: 500,
                  dateCreated: Value(defaultDate),
                  lastModifiedDate: defaultDate,
                  dataContentType: const Value(''),
                  isHidden: const Value(false),
                  path: '',
                );
              },
            ),
            ...List.generate(
              rootFolderFileCount,
              (i) {
                final fileId = '$conflictTestFolderId$i';
                return FileEntriesCompanion.insert(
                  id: fileId,
                  driveId: driveId,
                  parentFolderId: conflictTestFolderId,
                  name: fileId,
                  dataTxId: '${fileId}Data',
                  size: 500,
                  dateCreated: Value(defaultDate),
                  lastModifiedDate: defaultDate,
                  dataContentType: const Value(''),
                  isHidden: const Value(false),
                  path: '',
                );
              },
            ),
          ],
        );
        // Insert fake file revisions
        batch.insertAll(
          db.fileRevisions,
          [
            ...List.generate(
              rootFolderFileCount,
              (i) {
                final fileId = '$rootFolderId$i';
                return FileRevisionsCompanion.insert(
                    fileId: fileId,
                    driveId: driveId,
                    parentFolderId: rootFolderId,
                    name: fileId,
                    metadataTxId: '${fileId}Meta',
                    action: RevisionAction.create,
                    dataTxId: '${fileId}Data',
                    size: 500,
                    dateCreated: Value(defaultDate),
                    lastModifiedDate: defaultDate,
                    dataContentType: const Value(''),
                    isHidden: const Value(false));
              },
            ),
            ...List.generate(
              rootFolderFileCount,
              (i) {
                final fileId = '$conflictTestFolderId$i';
                return FileRevisionsCompanion.insert(
                    fileId: fileId,
                    driveId: driveId,
                    parentFolderId: conflictTestFolderId,
                    name: fileId,
                    metadataTxId: '${fileId}Meta',
                    action: RevisionAction.create,
                    dataTxId: '${fileId}Data',
                    size: 500,
                    dateCreated: Value(defaultDate),
                    lastModifiedDate: defaultDate,
                    dataContentType: const Value(''),
                    isHidden: const Value(false));
              },
            ),
          ],
        );
        // Insert fake metadata and data transactions
        batch.insertAll(
          db.networkTransactions,
          [
            ...List.generate(
              rootFolderFileCount,
              (i) {
                final fileId = '$rootFolderId$i';
                return NetworkTransactionsCompanion.insert(
                  id: '${fileId}Meta',
                  status: const Value(TransactionStatus.confirmed),
                  dateCreated: Value(defaultDate),
                );
              },
            ),
            ...List.generate(
              rootFolderFileCount,
              (i) {
                final fileId = '$rootFolderId$i';
                return NetworkTransactionsCompanion.insert(
                  id: '${fileId}Data',
                  status: const Value(TransactionStatus.confirmed),
                  dateCreated: Value(defaultDate),
                );
              },
            ),
            ...List.generate(
              rootFolderFileCount,
              (i) {
                final fileId = '$conflictTestFolderId$i';
                return NetworkTransactionsCompanion.insert(
                  id: '${fileId}Meta',
                  status: const Value(TransactionStatus.confirmed),
                  dateCreated: Value(defaultDate),
                );
              },
            ),
            ...List.generate(
              rootFolderFileCount,
              (i) {
                final fileId = '$conflictTestFolderId$i';
                return NetworkTransactionsCompanion.insert(
                  id: '${fileId}Data',
                  status: const Value(TransactionStatus.confirmed),
                  dateCreated: Value(defaultDate),
                );
              },
            ),
          ],
        );
      });

      driveDao = db.driveDao;
      AppPlatform.setMockPlatform(platform: SystemPlatform.unknown);
      arweave = MockArweaveService();
      when(() => arweave.postTx(any())).thenAnswer((_) async => Future.value());
      when(() => arweave.prepareEntityDataItem(any(), any(),
          key: any(named: 'key'),
          skipSignature: any(named: 'skipSignature'))).thenAnswer(
        (_) async => await getTestDataItem('test/fixtures/signed_v2_tx.json'),
      );
      when(() => arweave.prepareDataBundleTx(any(), any())).thenAnswer(
        (_) async =>
            await getTestTransaction('test/fixtures/signed_v2_tx.json'),
      );
      turboUploadService = DontUseUploadService();
      crypto = ArDriveCrypto();
      licenseService = MockLicenseService();
      costReader = _MockCostReader();
      profileCubit = MockProfileCubit();

      final keyBytes = Uint8List(32);
      fillBytesWithSecureRandom(keyBytes);
      final wallet = getTestWallet();
      when(profileCubit.logoutIfWalletMismatch)
          .thenAnswer((_) => Future.value(false));
      PackageInfo.setMockInitialValues(
        appName: 'fake-app-name',
        packageName: 'fake-package-name',
        version: 'fake-version',
        buildNumber: 'fake-build-number',
        buildSignature: 'fake-build-signature',
      );
      await AppInfoServices().loadAppInfo();

      when(() => profileCubit.state).thenReturn(
        ProfileLoggedIn(
          user: User(
            password: '123',
            wallet: wallet,
            cipherKey: SecretKey(keyBytes),
            walletAddress: await wallet.getAddress(),
            walletBalance: BigInt.one,
            profileType: ProfileType.json,
            ioTokens: 'ioTokens',
            errorFetchingIOTokens: false,
          ),
          useTurbo: false,
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });
    blocTest(
      'throws when selectedItems is empty',
      build: () => FsEntryLicenseBloc(
        arweave: arweave,
        turboUploadService: turboUploadService,
        driveId: driveId,
        driveDao: driveDao,
        profileCubit: profileCubit,
        crypto: crypto,
        licenseService: licenseService,
        costReader: costReader,
        selectedItems: [],
      ),
      errors: () => [isA<Exception>()],
    );
    blocTest(
      'successfully detect when no files',
      build: () => FsEntryLicenseBloc(
        arweave: arweave,
        turboUploadService: turboUploadService,
        driveId: driveId,
        driveDao: driveDao,
        profileCubit: profileCubit,
        crypto: crypto,
        licenseService: licenseService,
        costReader: costReader,
        // TODO: revisit this when we have a better way to mock the selected items
        selectedItems: [],
        platform: FakePlatform(operatingSystem: 'android'),
      ),
      act: (FsEntryLicenseBloc bloc) async {
        bloc.add(const FsEntryLicenseInitial());
        await Future.delayed(const Duration(seconds: 1));
      },
      wait: const Duration(seconds: 2),
      expect: () => [
        isA<FsEntryLicenseNoFiles>(),
      ],
    );
    group('the cost of the write', () {
      late MockTurboUploadService turbo;

      setUp(() {
        turbo = MockTurboUploadService();
        when(() => turbo.useTurboUpload).thenReturn(true);
        when(() => turbo.postDataItem(
              dataItem: any(named: 'dataItem'),
              wallet: any(named: 'wallet'),
            )).thenAnswer((_) async {});
      });

      void costs(UploadReviewSummary summary) => when(() => costReader.read(
            itemSizes: any(named: 'itemSizes'),
            wallet: any(named: 'wallet'),
            walletBalance: any(named: 'walletBalance'),
            refusedByTurbo: any(named: 'refusedByTurbo'),
          )).thenAnswer((_) async => summary);

      /// A bloc on the review of a license on the root folder's files.
      Future<FsEntryLicenseBloc> reviewing() async {
        final bloc = FsEntryLicenseBloc(
          arweave: arweave,
          turboUploadService: turbo,
          driveId: driveId,
          driveDao: driveDao,
          profileCubit: profileCubit,
          crypto: crypto,
          licenseService: LicenseService(),
          costReader: costReader,
          selectedItems: [_FakeItem()],
        );
        bloc.filesToLicense = [
          for (var i = 0; i < rootFolderFileCount; i++)
            await driveDao.fileById(fileId: '$rootFolderId$i').getSingle(),
        ];
        bloc.add(const FsEntryLicenseConfigurationSubmit());
        await bloc.stream.firstWhere(
            (s) => s is FsEntryLicenseReviewing && s.summary != null);
        return bloc;
      }

      Future<int> licensesSaved() async =>
          (await db.select(db.licenses).get()).length;

      test('the review reads the cost of exactly what it writes', () async {
        costs(_summary(isFree: true, isCovered: true));

        final bloc = await reviewing();

        final sizes = verify(() => costReader.read(
              itemSizes: captureAny(named: 'itemSizes'),
              wallet: any(named: 'wallet'),
              walletBalance: any(named: 'walletBalance'),
              refusedByTurbo: false,
            )).captured.single as List<int>;
        // A license assertion and new metadata for each file.
        expect(sizes, hasLength(rootFolderFileCount * 2));
        expect(sizes.every((s) => s > 1000), isTrue);
        // Nothing is posted or saved to price it.
        verifyNever(() => turbo.postDataItem(
            dataItem: any(named: 'dataItem'), wallet: any(named: 'wallet')));
        expect(await licensesSaved(), 0);
        await bloc.close();
      });

      test('free: Confirm writes the license to Turbo and saves it', () async {
        costs(_summary(isFree: true, isCovered: true));
        final bloc = await reviewing();

        bloc.add(const FsEntryLicenseReviewConfirm());
        await bloc.stream.firstWhere((s) => s is FsEntryLicenseSuccess);

        verify(() => turbo.postDataItem(
              dataItem: any(named: 'dataItem'),
              wallet: any(named: 'wallet'),
            )).called(rootFolderFileCount * 2);
        verifyNever(() => arweave.postTx(any()));
        expect(await licensesSaved(), rootFolderFileCount);
        await bloc.close();
      });

      test('covered by credits: Confirm writes it', () async {
        costs(_summary(isCovered: true));
        final bloc = await reviewing();

        bloc.add(const FsEntryLicenseReviewConfirm());
        await bloc.stream.firstWhere((s) => s is FsEntryLicenseSuccess);

        expect(await licensesSaved(), rootFolderFileCount);
        await bloc.close();
      });

      for (final (name, summary) in [
        ('the credits are short', _summary()),
        ('there is no price', _summary(priceUnavailable: true)),
      ]) {
        test('Confirm writes nothing when $name', () async {
          costs(summary);
          final bloc = await reviewing();
          final states = <FsEntryLicenseState>[];
          final sub = bloc.stream.listen(states.add);

          bloc.add(const FsEntryLicenseReviewConfirm());
          await Future.delayed(const Duration(milliseconds: 200));

          expect(states, isEmpty);
          verifyNever(() => turbo.postDataItem(
              dataItem: any(named: 'dataItem'), wallet: any(named: 'wallet')));
          verifyNever(() => arweave.postTx(any()));
          expect(await licensesSaved(), 0);
          await sub.cancel();
          await bloc.close();
        });
      }

      test(
          'refused as not paid for: back on the review, read again as '
          'refused, and nothing saved', () async {
        costs(_summary(isFree: true, isCovered: true));
        when(() => turbo.postDataItem(
              dataItem: any(named: 'dataItem'),
              wallet: any(named: 'wallet'),
            )).thenThrow(TurboPaymentRequiredException());
        final bloc = await reviewing();
        costs(_summary());

        bloc.add(const FsEntryLicenseReviewConfirm());
        final back = await bloc.stream.firstWhere(
                (s) => s is FsEntryLicenseReviewing && s.summary != null)
            as FsEntryLicenseReviewing;

        expect(back.summary!.needsCredits, isTrue);
        verify(() => costReader.read(
              itemSizes: any(named: 'itemSizes'),
              wallet: any(named: 'wallet'),
              walletBalance: any(named: 'walletBalance'),
              refusedByTurbo: true,
            )).called(1);
        expect(await licensesSaved(), 0);
        final file =
            await driveDao.fileById(fileId: '${rootFolderId}0').getSingle();
        expect(file.licenseTxId, equals(null));
        await bloc.close();
      });

      test('any other failure is a failure, with nothing saved', () async {
        costs(_summary(isFree: true, isCovered: true));
        when(() => turbo.postDataItem(
              dataItem: any(named: 'dataItem'),
              wallet: any(named: 'wallet'),
            )).thenThrow(Exception('network'));
        final bloc = await reviewing();

        bloc.add(const FsEntryLicenseReviewConfirm());
        await bloc.stream.firstWhere((s) => s is FsEntryLicenseFailure);

        expect(await licensesSaved(), 0);
        await bloc.close();
      });

      test('a cost that cannot be worked out is no price', () async {
        when(() => costReader.read(
              itemSizes: any(named: 'itemSizes'),
              wallet: any(named: 'wallet'),
              walletBalance: any(named: 'walletBalance'),
              refusedByTurbo: any(named: 'refusedByTurbo'),
            )).thenThrow(Exception('boom'));

        final bloc = await reviewing();

        final state = bloc.state as FsEntryLicenseReviewing;
        expect(state.summary!.priceUnavailable, isTrue);
        expect(state.summary!.isCovered, isFalse);
        await bloc.close();
      });

      test('Try again reads the cost again', () async {
        costs(_summary(priceUnavailable: true));
        final bloc = await reviewing();
        costs(_summary(isFree: true, isCovered: true));

        bloc.add(const FsEntryLicenseCostRefresh());
        final state = await bloc.stream.firstWhere(
                (s) => s is FsEntryLicenseReviewing && s.summary != null)
            as FsEntryLicenseReviewing;

        expect(state.summary!.isFree, isTrue);
        await bloc.close();
      });
    });
  });
}

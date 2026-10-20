import 'package:ardrive/core/arfs/use_cases/bulk_import_files.dart';
import 'package:ardrive/core/arfs/use_cases/upload_file_metadata.dart';
import 'package:ardrive/core/arfs/use_cases/upload_folder_metadata.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../test_utils/utils.dart';

class MockUploadFileMetadata extends Mock implements UploadFileMetadata {}

class MockUploadFolderMetadata extends Mock implements UploadFolderMetadata {}

const driveId = 'drive-id';
const rootFolderId = 'root-folder-id';

/// A manifest entry whose data transaction is [dataTxId].
ManifestFileEntry manifestFile(String path, String dataTxId) =>
    ManifestFileEntry(
      id: 'file-$dataTxId',
      path: path,
      name: path.split('/').last,
      dataTxId: dataTxId,
      contentType: 'text/plain',
      size: 1,
    );

void main() {
  late Database db;
  late MockUploadFileMetadata uploadFileMetadata;
  late MockUploadFolderMetadata uploadFolderMetadata;
  late MockArweaveService arweaveService;
  late MockArDriveAuth arDriveAuth;
  late BulkImportFiles bulkImportFiles;

  setUpAll(() {
    registerFallbackValue(FileEntity());
    registerFallbackValue(FolderEntity());
    registerFallbackValue(getTestWallet());
  });

  setUp(() async {
    db = getTestDb();
    await db.batch((batch) {
      batch.insert(
        db.drives,
        DrivesCompanion.insert(
          id: driveId,
          rootFolderId: rootFolderId,
          ownerAddress: 'owner-address',
          name: 'drive',
          privacy: DrivePrivacyTag.public,
        ),
      );
      batch.insert(
        db.folderEntries,
        FolderEntriesCompanion.insert(
          id: rootFolderId,
          driveId: driveId,
          name: 'drive',
          isHidden: const Value(false),
          path: '',
        ),
      );
    });

    uploadFileMetadata = MockUploadFileMetadata();
    uploadFolderMetadata = MockUploadFolderMetadata();
    arweaveService = MockArweaveService();
    arDriveAuth = MockArDriveAuth();

    when(() => uploadFolderMetadata(
          folderEntity: any(named: 'folderEntity'),
          customTags: any(named: 'customTags'),
          isPrivate: any(named: 'isPrivate'),
          wallet: any(named: 'wallet'),
          driveKey: any(named: 'driveKey'),
        )).thenAnswer((invocation) async {
      final folder = invocation.namedArguments[#folderEntity] as FolderEntity;
      return FolderMetadataUploadResult(
        metadataTxId: 'folder-meta-${folder.id}',
        tags: [],
      );
    });

    // The metadata of any file named `bad.txt` is refused; the rest upload
    // after a short wait, so that the pool's tasks overlap.
    when(() => uploadFileMetadata(
          fileEntity: any(named: 'fileEntity'),
          customTags: any(named: 'customTags'),
          isPrivate: any(named: 'isPrivate'),
          wallet: any(named: 'wallet'),
        )).thenAnswer((invocation) async {
      final file = invocation.namedArguments[#fileEntity] as FileEntity;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if (file.name == 'bad.txt') {
        throw FileMetadataUploadException('refused');
      }
      return FileMetadataUploadResult(
        metadataTxId: 'file-meta-${file.id}',
        tags: [],
      );
    });

    bulkImportFiles = BulkImportFiles(
      uploadFileMetadata: uploadFileMetadata,
      uploadFolderMetadata: uploadFolderMetadata,
      driveDao: db.driveDao,
      arweaveService: arweaveService,
      arDriveAuth: arDriveAuth,
    );
  });

  tearDown(() => db.close());

  void givenProfileType(ProfileType profileType) {
    when(() => arDriveAuth.currentUser)
        .thenReturn(getTestUser().copyWith(profileType: profileType));
  }

  void givenSizesAndTypes(List<Map<String, DataTxSizeAndType?>> batches) {
    when(() => arweaveService.getSizeAndTypeOfDataTxs(any()))
        .thenAnswer((_) => Stream.fromIterable(batches));
  }

  Future<BulkImportResult> runImport(
    List<ManifestFileEntry> files, {
    void Function(String path)? onFileFailure,
  }) =>
      bulkImportFiles(
        driveId: driveId,
        parentFolderId: rootFolderId,
        files: files,
        wallet: getTestWallet(),
        userCipherKey: getTestUser().cipherKey,
        manifestTxId: 'manifest-tx-id',
        originalOwnerAddress: 'original-owner',
        onFileFailure: onFileFailure,
      ).timeout(const Duration(seconds: 10));

  const described = DataTxSizeAndType(size: 1, contentType: 'text/plain');

  // ArConnect imports one file at a time; other wallets five at once.
  for (final profileType in ProfileType.values) {
    test(
        'a partial failure lists every imported and failed file, by manifest '
        'path, with ${profileType.name} concurrency', () async {
      givenProfileType(profileType);
      givenSizesAndTypes([
        {
          'tx-1': described,
          'tx-2': described,
          'tx-3': described,
          'tx-4': null,
          'tx-5': described,
        },
        {'tx-6': described, 'tx-7': described},
      ]);
      final reportedFailures = <String>[];

      final result = await runImport(
        [
          manifestFile('index.html', 'tx-1'),
          manifestFile('docs/readme.txt', 'tx-2'),
          manifestFile('img/bad.txt', 'tx-3'),
          manifestFile('unreadable.txt', 'tx-4'),
          manifestFile('docs/guide.txt', 'tx-5'),
          manifestFile('docs/deep/bad.txt', 'tx-6'),
          manifestFile('last.txt', 'tx-7'),
        ],
        onFileFailure: reportedFailures.add,
      );

      expect(
        result.importedFiles.map((f) => f.dataTxId),
        unorderedEquals(['tx-1', 'tx-2', 'tx-5', 'tx-7']),
      );
      expect(
        result.failures.map((f) => f.path),
        unorderedEquals(['img/bad.txt', 'unreadable.txt', 'docs/deep/bad.txt']),
      );
      expect(
        result.failures.map((f) => f.dataTxId),
        unorderedEquals(['tx-3', 'tx-4', 'tx-6']),
      );
      expect(reportedFailures,
          unorderedEquals(result.failures.map((f) => f.path)));

      // The refused upload keeps its cause, which is how a payment
      // rejection is recognised.
      final refused =
          result.failures.firstWhere((f) => f.path == 'img/bad.txt');
      expect(refused.originalError, isA<FileMetadataUploadException>());
    });
  }

  test('a batch in which every file fails still completes the import',
      () async {
    givenProfileType(ProfileType.json);
    givenSizesAndTypes([
      {'tx-1': null, 'tx-2': null},
      {'tx-3': described},
    ]);
    final reportedFailures = <String>[];

    final result = await runImport(
      [
        manifestFile('a/one.txt', 'tx-1'),
        manifestFile('two.txt', 'tx-2'),
        manifestFile('three.txt', 'tx-3'),
      ],
      onFileFailure: reportedFailures.add,
    );

    expect(result.importedFiles.map((f) => f.dataTxId), ['tx-3']);
    expect(
      result.failures.map((f) => f.path),
      unorderedEquals(['a/one.txt', 'two.txt']),
    );
    expect(reportedFailures, unorderedEquals(['a/one.txt', 'two.txt']));
  });

  test('when every file fails, nothing is imported and each is listed',
      () async {
    givenProfileType(ProfileType.json);
    givenSizesAndTypes([
      {'tx-1': described, 'tx-2': null},
    ]);

    final result = await runImport([
      manifestFile('img/bad.txt', 'tx-1'),
      manifestFile('missing.txt', 'tx-2'),
    ]);

    expect(result.importedFiles, isEmpty);
    expect(
      result.failures.map((f) => f.path),
      unorderedEquals(['img/bad.txt', 'missing.txt']),
    );
  });

  test('a failure of the whole call throws BulkImportException', () async {
    givenProfileType(ProfileType.json);
    when(() => arweaveService.getSizeAndTypeOfDataTxs(any()))
        .thenAnswer((_) => Stream.error(Exception('gateway down')));

    await expectLater(
      runImport([manifestFile('one.txt', 'tx-1')]),
      throwsA(isA<BulkImportException>()),
    );
  });
}

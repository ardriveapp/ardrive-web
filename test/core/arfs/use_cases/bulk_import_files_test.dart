import 'package:ardrive/core/arfs/repository/file_metadata_repository.dart';
import 'package:ardrive/core/arfs/use_cases/bulk_import_files.dart';
import 'package:ardrive/core/arfs/use_cases/insert_file_metadata.dart';
import 'package:ardrive/core/arfs/use_cases/verify_parent_folder.dart';
import 'package:ardrive/manifests/domain/entities/manifest.dart';
import 'package:ardrive/models/models.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockVerifyParentFolder extends Mock implements VerifyParentFolder {}

class MockInsertFileMetadata extends Mock implements InsertFileMetadata {}

void main() {
  late BulkImportFiles useCase;
  late MockVerifyParentFolder verifyParentFolder;
  late MockInsertFileMetadata insertFileMetadata;

  setUp(() {
    verifyParentFolder = MockVerifyParentFolder();
    insertFileMetadata = MockInsertFileMetadata();

    useCase = BulkImportFiles(
      verifyParentFolder: verifyParentFolder,
      insertFileMetadata: insertFileMetadata,
    );

    registerFallbackValue(FileMetadata(
      id: 'test-id',
      name: 'test-name',
      dataTxId: 'test-tx-id',
      contentType: 'text/plain',
      size: 1000,
      lastModifiedDate: DateTime(2024),
    ));
  });

  group('BulkImportFiles', () {
    const testDriveId = 'test-drive-id';
    const testParentFolderId = 'test-parent-folder-id';

    final testFolder = FolderEntry(
      id: testParentFolderId,
      driveId: testDriveId,
      name: 'Test Folder',
      path: '/test',
      isHidden: false,
      dateCreated: DateTime(2024),
      lastUpdated: DateTime(2024),
      parentFolderId: Value('parent-id'),
      isGhost: false,
    );

    final testFileEntry = FileEntry(
      id: 'file1',
      driveId: testDriveId,
      name: 'test-file.txt',
      size: 1024,
      lastUpdated: DateTime(2024),
      dateCreated: DateTime(2024),
      lastModifiedDate: DateTime(2024),
      dataContentType: 'text/plain',
      dataTxId: 'data-tx-id',
      parentFolderId: testParentFolderId,
      path: '/test/test-file.txt',
      isHidden: false,
    );

    final testManifest = Manifest(
      manifest: 'arweave/paths',
      version: '0.1.0',
      paths: {
        'test-file.txt': {
          'id': 'data-tx-id',
          'contentType': 'text/plain',
        },
        'folder1/test-file2.txt': {
          'id': 'data-tx-id-2',
          'contentType': 'text/plain',
        },
        'folder1/subfolder/test-file3.txt': {
          'id': 'data-tx-id-3',
          'contentType': 'text/plain',
        },
      },
    );

    test('successfully imports files with folder hierarchy', () async {
      // Setup mocks for initial parent folder verification
      when(() => verifyParentFolder(
            driveId: testDriveId,
            parentFolderId: testParentFolderId,
          )).thenAnswer((_) async => testFolder);

      // Setup mocks for folder1 creation
      final folder1 = testFolder.copyWith(
        id: 'folder1-id',
        name: 'folder1',
        parentFolderId: Value(testParentFolderId),
      );
      when(() => verifyParentFolder(
            driveId: testDriveId,
            parentFolderId: testParentFolderId,
            folderName: 'folder1',
          )).thenAnswer((_) async => folder1);

      // Setup mocks for subfolder creation
      final subfolder = testFolder.copyWith(
        id: 'subfolder-id',
        name: 'subfolder',
        parentFolderId: Value('folder1-id'),
      );
      when(() => verifyParentFolder(
            driveId: testDriveId,
            parentFolderId: 'folder1-id',
            folderName: 'subfolder',
          )).thenAnswer((_) async => subfolder);

      // Setup mocks for file creation
      when(() => insertFileMetadata(
            any(),
            driveId: testDriveId,
            parentFolderId: any(named: 'parentFolderId'),
          )).thenAnswer((_) async => testFileEntry);

      // Execute use case
      final result = await useCase(
        manifest: testManifest,
        driveId: testDriveId,
        parentFolderId: testParentFolderId,
      );

      // Verify result
      expect(result.importedFiles.length, 3);
      expect(result.failures.isEmpty, true);

      // Verify folder verifications
      verify(() => verifyParentFolder(
            driveId: testDriveId,
            parentFolderId: testParentFolderId,
          )).called(1);
      verify(() => verifyParentFolder(
            driveId: testDriveId,
            parentFolderId: testParentFolderId,
            folderName: 'folder1',
          )).called(1);
      verify(() => verifyParentFolder(
            driveId: testDriveId,
            parentFolderId: 'folder1-id',
            folderName: 'subfolder',
          )).called(1);

      // Verify file insertions
      verify(() => insertFileMetadata(
            any(
                that: predicate((FileMetadata m) =>
                    m.name == 'test-file.txt' && m.dataTxId == 'data-tx-id')),
            driveId: testDriveId,
            parentFolderId: testParentFolderId,
          )).called(1);
      verify(() => insertFileMetadata(
            any(
                that: predicate((FileMetadata m) =>
                    m.name == 'test-file2.txt' &&
                    m.dataTxId == 'data-tx-id-2')),
            driveId: testDriveId,
            parentFolderId: 'folder1-id',
          )).called(1);
      verify(() => insertFileMetadata(
            any(
                that: predicate((FileMetadata m) =>
                    m.name == 'test-file3.txt' &&
                    m.dataTxId == 'data-tx-id-3')),
            driveId: testDriveId,
            parentFolderId: 'subfolder-id',
          )).called(1);
    });

    test('handles folder creation failures', () async {
      // Setup mocks for initial parent folder verification
      when(() => verifyParentFolder(
            driveId: testDriveId,
            parentFolderId: testParentFolderId,
          )).thenAnswer((_) async => testFolder);

      // Setup mock for folder1 creation to fail
      when(() => verifyParentFolder(
            driveId: testDriveId,
            parentFolderId: testParentFolderId,
            folderName: 'folder1',
          )).thenThrow(Exception('Failed to create folder'));

      // Setup mock for root file creation
      when(() => insertFileMetadata(
            any(
                that: predicate((FileMetadata m) =>
                    m.name == 'test-file.txt' && m.dataTxId == 'data-tx-id')),
            driveId: testDriveId,
            parentFolderId: testParentFolderId,
          )).thenAnswer((_) async => testFileEntry);

      // Execute use case
      final result = await useCase(
        manifest: testManifest,
        driveId: testDriveId,
        parentFolderId: testParentFolderId,
      );

      // Verify result
      expect(result.importedFiles.length, 1); // Only root file should succeed
      expect(result.failures.length, 2); // Files in folder1 should fail
      expect(
          result.failures
              .every((f) => f.error.contains('Failed to create folder')),
          true);

      // Verify interactions
      verify(() => verifyParentFolder(
            driveId: testDriveId,
            parentFolderId: testParentFolderId,
          )).called(1);
      verify(() => insertFileMetadata(
            any(
                that: predicate((FileMetadata m) =>
                    m.name == 'test-file.txt' && m.dataTxId == 'data-tx-id')),
            driveId: testDriveId,
            parentFolderId: testParentFolderId,
          )).called(1);
    });

    test('handles progress callback correctly', () async {
      // Setup mocks
      when(() => verifyParentFolder(
            driveId: any(named: 'driveId'),
            parentFolderId: any(named: 'parentFolderId'),
            folderName: any(named: 'folderName'),
          )).thenAnswer((_) async => testFolder);

      when(() => insertFileMetadata(
            any(),
            driveId: any(named: 'driveId'),
            parentFolderId: any(named: 'parentFolderId'),
          )).thenAnswer((_) async => testFileEntry);

      final progressUpdates = <String>[];
      final processedCounts = <int>[];
      final failedFiles = <List<String>>[];

      // Execute use case with progress callback
      await useCase(
        manifest: testManifest,
        driveId: testDriveId,
        parentFolderId: testParentFolderId,
        onProgress: (fileName, processed, failed) {
          progressUpdates.add(fileName);
          processedCounts.add(processed);
          failedFiles.add(failed);
        },
      );

      // Verify progress updates
      expect(progressUpdates.length, 3);
      expect(processedCounts, [1, 2, 3]);
      expect(failedFiles.every((f) => f.isEmpty), true);
    });
  });
}

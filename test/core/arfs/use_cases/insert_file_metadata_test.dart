import 'package:ardrive/core/arfs/repository/file_metadata_repository.dart';
import 'package:ardrive/core/arfs/use_cases/insert_file_metadata.dart';
import 'package:ardrive/models/models.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDriveDao extends Mock implements DriveDao {
  @override
  Selectable<FileEntry> fileById({
    required String driveId,
    required String fileId,
  }) {
    return MockSelectable<FileEntry>();
  }
}

class MockSelectable<T> extends Mock implements Selectable<T> {
  @override
  Future<T?> getSingleOrNull() async => null;

  @override
  Future<T> getSingle() async => throw UnimplementedError();
}

void main() {
  late InsertFileMetadata useCase;
  late MockDriveDao driveDao;
  late MockSelectable<FileEntry> fileQuery;

  setUp(() {
    driveDao = MockDriveDao();
    useCase = InsertFileMetadata(driveDao);
    fileQuery = MockSelectable<FileEntry>();

    when(() => driveDao.fileById(
          driveId: any(named: 'driveId'),
          fileId: any(named: 'fileId'),
        )).thenReturn(fileQuery);
  });

  group('InsertFileMetadata', () {
    const testDriveId = 'test-drive-id';
    const testFileId = 'test-file-id';
    const testParentFolderId = 'test-parent-folder-id';

    final testMetadata = FileMetadata(
      id: testFileId,
      name: 'test-file.txt',
      dataTxId: 'data-tx-id',
      contentType: 'text/plain',
      size: 1024,
      lastModifiedDate: DateTime(2024),
      customMetadata: {'key': 'value'},
    );

    final testFileEntry = FileEntry(
      id: testFileId,
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

    test('successfully inserts new file metadata', () async {
      // Setup mocks
      when(() => fileQuery.getSingleOrNull()).thenAnswer((_) async => null);
      when(() => fileQuery.getSingle()).thenAnswer((_) async => testFileEntry);
      when(() => driveDao.transaction<void>(any())).thenAnswer((_) async {});

      // Execute use case
      final result = await useCase(
        testMetadata,
        driveId: testDriveId,
        parentFolderId: testParentFolderId,
      );

      // Verify result
      expect(result, testFileEntry);

      // Verify interactions
      verify(() => driveDao.fileById(
            driveId: testDriveId,
            fileId: testFileId,
          )).called(2); // Once for check, once for final fetch
      verify(() => driveDao.transaction<void>(any())).called(1);
    });

    test('successfully updates existing file metadata', () async {
      // Setup mocks
      when(() => fileQuery.getSingleOrNull())
          .thenAnswer((_) async => testFileEntry);
      when(() => fileQuery.getSingle()).thenAnswer((_) async => testFileEntry);
      when(() => driveDao.transaction<void>(any())).thenAnswer((_) async {});

      // Execute use case
      final result = await useCase(
        testMetadata,
        driveId: testDriveId,
        parentFolderId: testParentFolderId,
      );

      // Verify result
      expect(result, testFileEntry);

      // Verify interactions
      verify(() => driveDao.fileById(
            driveId: testDriveId,
            fileId: testFileId,
          )).called(2); // Once for check, once for final fetch
      verify(() => driveDao.transaction<void>(any())).called(1);
    });

    test('throws FileMetadataInsertionException when insertion fails',
        () async {
      // Setup mocks
      when(() => fileQuery.getSingleOrNull()).thenAnswer((_) async => null);
      when(() => driveDao.transaction<void>(any()))
          .thenThrow(Exception('Database error'));

      // Execute and verify
      expect(
        () => useCase(
          testMetadata,
          driveId: testDriveId,
          parentFolderId: testParentFolderId,
        ),
        throwsA(isA<FileMetadataInsertionException>().having(
          (e) => e.message,
          'message',
          'Failed to insert file metadata',
        )),
      );
    });
  });
}

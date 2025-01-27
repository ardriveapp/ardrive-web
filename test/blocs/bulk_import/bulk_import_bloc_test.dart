import 'package:ardrive/blocs/bulk_import/bulk_import_bloc.dart';
import 'package:ardrive/blocs/bulk_import/bulk_import_event.dart';
import 'package:ardrive/blocs/bulk_import/bulk_import_state.dart';
import 'package:ardrive/core/arfs/use_cases/bulk_import_files.dart';
import 'package:ardrive/models/models.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockBulkImportFiles extends Mock implements BulkImportFiles {}

void main() {
  late BulkImportBloc bloc;
  late MockBulkImportFiles bulkImportFiles;

  setUp(() {
    bulkImportFiles = MockBulkImportFiles();
    bloc = BulkImportBloc(bulkImportFiles: bulkImportFiles);
  });

  tearDown(() {
    bloc.close();
  });

  group('BulkImportBloc', () {
    const testDriveId = 'test-drive-id';
    const testParentFolderId = 'test-parent-folder-id';
    final testFileIds = ['file1', 'file2', 'file3'];

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

    final testResult = BulkImportResult(
      importedFiles: [testFileEntry, testFileEntry, testFileEntry],
      failures: [],
    );

    test('initial state is BulkImportInitial', () {
      expect(bloc.state, isA<BulkImportInitial>());
    });

    blocTest<BulkImportBloc, BulkImportState>(
      'emits progress states and success state when import succeeds',
      build: () {
        when(() => bulkImportFiles(
              fileIds: testFileIds,
              driveId: testDriveId,
              parentFolderId: testParentFolderId,
            )).thenAnswer((_) async => testResult);
        return bloc;
      },
      act: (bloc) => bloc.add(StartBulkImport(
        fileIds: testFileIds,
        driveId: testDriveId,
        parentFolderId: testParentFolderId,
      )),
      expect: () => [
        const BulkImportInProgress(
          message: 'Starting bulk import...',
          progress: 0,
        ),
        const BulkImportInProgress(
          message: 'Verifying parent folder...',
          progress: 0.1,
        ),
        BulkImportInProgress(
          message: 'Import completed with 3 successful imports and 0 failures.',
          progress: 1.0,
        ),
        BulkImportSuccess(testResult),
      ],
      verify: (_) {
        verify(() => bulkImportFiles(
              fileIds: testFileIds,
              driveId: testDriveId,
              parentFolderId: testParentFolderId,
            )).called(1);
      },
    );

    blocTest<BulkImportBloc, BulkImportState>(
      'emits error state when import fails',
      build: () {
        when(() => bulkImportFiles(
              fileIds: testFileIds,
              driveId: testDriveId,
              parentFolderId: testParentFolderId,
            )).thenThrow(Exception('Import failed'));
        return bloc;
      },
      act: (bloc) => bloc.add(StartBulkImport(
        fileIds: testFileIds,
        driveId: testDriveId,
        parentFolderId: testParentFolderId,
      )),
      expect: () => [
        const BulkImportInProgress(
          message: 'Starting bulk import...',
          progress: 0,
        ),
        const BulkImportInProgress(
          message: 'Verifying parent folder...',
          progress: 0.1,
        ),
        isA<BulkImportError>()
            .having(
                (e) => e.message, 'message', 'Failed to perform bulk import')
            .having((e) => e.error, 'error', isA<Exception>()),
      ],
    );

    blocTest<BulkImportBloc, BulkImportState>(
      'emits error state when cancelled',
      build: () => bloc,
      act: (bloc) => bloc.add(CancelBulkImport()),
      expect: () => [
        const BulkImportError(
          message: 'Import cancelled by user',
        ),
      ],
    );

    blocTest<BulkImportBloc, BulkImportState>(
      'emits initial state when reset',
      build: () => bloc,
      act: (bloc) => bloc.add(ResetBulkImport()),
      expect: () => [BulkImportInitial()],
    );
  });
}

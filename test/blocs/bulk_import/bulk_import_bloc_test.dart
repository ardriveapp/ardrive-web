import 'package:ardrive/blocs/bulk_import/bulk_import_bloc.dart';
import 'package:ardrive/blocs/bulk_import/bulk_import_event.dart';
import 'package:ardrive/blocs/bulk_import/bulk_import_state.dart';
import 'package:ardrive/core/arfs/use_cases/bulk_import_files.dart';
import 'package:ardrive/core/arfs/use_cases/check_folder_conflicts.dart';
import 'package:ardrive/core/arfs/use_cases/upload_file_metadata.dart';
import 'package:ardrive/manifests/domain/entities/manifest.dart';
import 'package:ardrive/manifests/domain/models/manifest_result.dart';
import 'package:ardrive/manifests/domain/repositories/manifest_repository.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';

class MockBulkImportFiles extends Mock implements BulkImportFiles {}

class MockManifestRepository extends Mock implements ManifestRepository {}

class MockCheckFolderConflicts extends Mock implements CheckFolderConflicts {}

class FakeFileEntry extends Fake implements FileEntry {}

const manifestTxId = 'manifest-tx-id';
const driveId = 'drive-id';
const parentFolderId = 'parent-folder-id';

const paths = ['index.html', 'docs/readme.txt', 'img/bad.txt'];

/// A callback the use case makes while it runs.
sealed class Step {}

class Imported extends Step {
  final String name;
  Imported(this.name);
}

class Failed extends Step {
  final String path;
  Failed(this.path);
}

FileImportFailure failure(String path, [Object? originalError]) =>
    FileImportFailure(
      path: path,
      dataTxId: 'tx-$path',
      error: 'failed',
      originalError: originalError,
    );

BulkImportResult result(
        {required int imported, required List<String> failed}) =>
    BulkImportResult(
      importedFiles: List.generate(imported, (_) => FakeFileEntry()),
      failures: failed.map(failure).toList(),
    );

void main() {
  late MockBulkImportFiles bulkImportFiles;
  late MockManifestRepository manifestRepository;
  late MockCheckFolderConflicts checkFolderConflicts;
  late MockArDriveAuth ardriveAuth;

  setUpAll(() {
    registerFallbackValue(getTestWallet());
    registerFallbackValue(SecretKey([]));
    registerFallbackValue(<ManifestFileEntry>[]);
    registerFallbackValue(<FileConflictCheck>[]);
  });

  setUp(() {
    bulkImportFiles = MockBulkImportFiles();
    manifestRepository = MockManifestRepository();
    checkFolderConflicts = MockCheckFolderConflicts();
    ardriveAuth = MockArDriveAuth();

    when(() => ardriveAuth.currentUser).thenReturn(getTestUser());
    when(() => manifestRepository.getManifest(manifestTxId)).thenAnswer(
      (_) async => ManifestResult.success(
        Manifest(
          manifest: 'arweave/paths',
          version: '0.2.0',
          paths: {
            for (final path in paths) path: {'id': 'tx-$path'},
          },
        ),
        'original-owner',
      ),
    );
    when(() => checkFolderConflicts(
          driveId: any(named: 'driveId'),
          targetFolderId: any(named: 'targetFolderId'),
          files: any(named: 'files'),
        )).thenAnswer(
      (_) async => const FolderConflictResult(
        conflicts: [],
        hasConflicts: false,
      ),
    );
  });

  /// The use case makes the callbacks in [steps], then returns [returns], or
  /// throws [throws] when that is given instead.
  void givenImport(
    List<Step> steps, {
    BulkImportResult? returns,
    Object? throws,
  }) {
    when(() => bulkImportFiles(
          driveId: any(named: 'driveId'),
          parentFolderId: any(named: 'parentFolderId'),
          files: any(named: 'files'),
          wallet: any(named: 'wallet'),
          userCipherKey: any(named: 'userCipherKey'),
          onFolderProgress: any(named: 'onFolderProgress'),
          onFileProgress: any(named: 'onFileProgress'),
          onFileUploadSuccess: any(named: 'onFileUploadSuccess'),
          onFileFailure: any(named: 'onFileFailure'),
          onCreateFolderHierarchyStart:
              any(named: 'onCreateFolderHierarchyStart'),
          onCreateFolderHierarchyEnd: any(named: 'onCreateFolderHierarchyEnd'),
          manifestTxId: any(named: 'manifestTxId'),
          originalOwnerAddress: any(named: 'originalOwnerAddress'),
        )).thenAnswer((invocation) async {
      final args = invocation.namedArguments;
      final onFileProgress = args[#onFileProgress] as void Function(String)?;
      final onFileUploadSuccess =
          args[#onFileUploadSuccess] as void Function(String)?;
      final onFileFailure = args[#onFileFailure] as void Function(String)?;

      (args[#onCreateFolderHierarchyStart] as void Function()?)?.call();
      (args[#onCreateFolderHierarchyEnd] as void Function()?)?.call();

      for (final step in steps) {
        await Future<void>.delayed(Duration.zero);
        switch (step) {
          case Imported(:final name):
            onFileProgress?.call(name);
            onFileUploadSuccess?.call(name);
          case Failed(:final path):
            onFileFailure?.call(path);
        }
      }

      if (throws != null) throw throws;
      return returns!;
    });
  }

  BulkImportBloc buildBloc() => BulkImportBloc(
        bulkImportFiles: bulkImportFiles,
        manifestRepository: manifestRepository,
        ardriveAuth: ardriveAuth,
        checkFolderConflicts: checkFolderConflicts,
      );

  /// Loads the manifest, confirms the import of every file in it, and waits
  /// for the outcome: closing the bloc any sooner would drop it.
  Future<void> importManifest(BulkImportBloc bloc) async {
    bloc.add(const StartManifestBulkImport(
      manifestTxId: manifestTxId,
      driveId: driveId,
      parentFolderId: parentFolderId,
    ));
    final review = await bloc.stream
            .firstWhere((state) => state is BulkImportReviewingManifest)
        as BulkImportReviewingManifest;
    bloc.add(ConfirmManifestBulkImport(
      manifestTxId: manifestTxId,
      driveId: driveId,
      parentFolderId: parentFolderId,
      files: review.files,
    ));
    await bloc.stream.firstWhere(
      (state) => state is BulkImportSuccess || state is BulkImportError,
    );
  }

  Matcher isSuccess({required int successful, required int failed}) =>
      isA<BulkImportSuccess>()
          .having((s) => s.totalFiles, 'totalFiles', paths.length)
          .having((s) => s.successfulFiles, 'successfulFiles', successful)
          .having((s) => s.failedFiles, 'failedFiles', failed);

  Matcher isNothingImported() => isA<BulkImportError>().having(
      (s) => s.message, 'message', contains('Failed to import any files'));

  group('BulkImportBloc reports the outcome of an import', () {
    blocTest<BulkImportBloc, BulkImportState>(
      'when every file is imported',
      setUp: () => givenImport(
        [Imported('index.html'), Imported('readme.txt'), Imported('bad.txt')],
        returns: result(imported: 3, failed: []),
      ),
      build: buildBloc,
      act: importManifest,
      verify: (bloc) => expect(bloc.state, isSuccess(successful: 3, failed: 0)),
    );

    blocTest<BulkImportBloc, BulkImportState>(
      'when some files fail, showing each failure as it happens',
      setUp: () => givenImport(
        [Imported('index.html'), Failed('img/bad.txt'), Imported('readme.txt')],
        returns: result(imported: 2, failed: ['img/bad.txt']),
      ),
      build: buildBloc,
      act: importManifest,
      expect: () => containsAllInOrder([
        isA<BulkImportInProgress>().having(
            (s) => s.failedPaths, 'failedPaths', [
          'img/bad.txt'
        ]).having((s) => s.processedFiles, 'processedFiles', 1),
        isSuccess(successful: 2, failed: 1),
      ]),
    );

    blocTest<BulkImportBloc, BulkImportState>(
      'when every file fails',
      setUp: () => givenImport(
        [for (final path in paths) Failed(path)],
        returns: result(imported: 0, failed: paths),
      ),
      build: buildBloc,
      act: importManifest,
      verify: (bloc) => expect(
        bloc.state,
        allOf(
          isNothingImported(),
          isA<BulkImportError>()
              .having((s) => s.isPaymentError, 'isPaymentError', isFalse),
        ),
      ),
    );

    blocTest<BulkImportBloc, BulkImportState>(
      'when every file is refused for payment',
      setUp: () => givenImport(
        [for (final path in paths) Failed(path)],
        returns: BulkImportResult(
          importedFiles: [],
          failures: [
            for (final path in paths)
              failure(
                path,
                FileMetadataUploadException(
                  'refused',
                  originalError: TurboPaymentRequiredException(),
                ),
              ),
          ],
        ),
      ),
      build: buildBloc,
      act: importManifest,
      verify: (bloc) => expect(
        bloc.state,
        isA<BulkImportError>()
            .having((s) => s.isPaymentError, 'isPaymentError', isTrue),
      ),
    );

    blocTest<BulkImportBloc, BulkImportState>(
      'when the whole import fails part-way, counting the files it left out',
      setUp: () => givenImport(
        [Imported('index.html')],
        throws: BulkImportException('Bulk import failed'),
      ),
      build: buildBloc,
      act: importManifest,
      verify: (bloc) => expect(bloc.state, isSuccess(successful: 1, failed: 2)),
    );

    blocTest<BulkImportBloc, BulkImportState>(
      'when the whole import fails before any file is imported',
      setUp: () => givenImport(
        [],
        throws: BulkImportException('Failed to create folder: docs'),
      ),
      build: buildBloc,
      act: importManifest,
      verify: (bloc) => expect(
        bloc.state,
        allOf(
          isNothingImported(),
          isA<BulkImportError>()
              .having((s) => s.error, 'error', isA<BulkImportException>()),
        ),
      ),
    );
  });
}

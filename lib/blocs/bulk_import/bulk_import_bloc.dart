import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/bulk_import/bulk_import_event.dart';
import 'package:ardrive/blocs/bulk_import/bulk_import_state.dart';
import 'package:ardrive/core/arfs/use_cases/bulk_import_files.dart';
import 'package:ardrive/manifests/domain/repositories/manifest_repository.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:bloc/bloc.dart';

/// BLoC for managing the bulk import process.
class BulkImportBloc extends Bloc<BulkImportEvent, BulkImportState> {
  final BulkImportFiles _bulkImportFiles;
  final ManifestRepository _manifestRepository;
  final ArDriveAuth _ardriveAuth;

  BulkImportBloc({
    required BulkImportFiles bulkImportFiles,
    required ManifestRepository manifestRepository,
    required ArDriveAuth ardriveAuth,
  })  : _bulkImportFiles = bulkImportFiles,
        _manifestRepository = manifestRepository,
        _ardriveAuth = ardriveAuth,
        super(const BulkImportInitial()) {
    on<StartManifestBulkImport>(_onStartManifestBulkImport);
    on<CancelBulkImport>(_onCancelBulkImport);
    on<ResetBulkImport>(_onResetBulkImport);
  }

  Future<void> _onStartManifestBulkImport(
    StartManifestBulkImport event,
    Emitter<BulkImportState> emit,
  ) async {
    try {
      emit(BulkImportLoadingManifest(event.manifestTxId));

      // Get manifest data
      final manifestResult =
          await _manifestRepository.getManifest(event.manifestTxId);

      if (manifestResult.failure != null) {
        emit(BulkImportError(
          'Failed to load manifest: ${manifestResult.failure!.message}',
        ));
        return;
      }

      final manifest = manifestResult.manifest!;

      // Convert manifest paths to ManifestFileEntry objects
      final files = manifest.paths.entries.map((entry) {
        final path = entry.key;
        final data = entry.value;
        return ManifestFileEntry(
          id: data['id'] as String,
          path: path,
          name: path.split('/').last,
          dataTxId: data['id'] as String,
          contentType:
              data['contentType'] as String? ?? 'application/octet-stream',
          size: data['size'] as int? ?? 0,
        );
      }).toList();

      // Start importing files
      emit(BulkImportInProgress(
        manifestTxId: event.manifestTxId,
        fileIds: files.map((f) => f.id).toList(),
        processedFiles: 0,
        failedFiles: [],
        currentFileName: 'Starting import...',
        failedPaths: [],
        isCreatingFolderHierarchy: true,
      ));

      var processedFiles = 0;
      final failedPaths = <String>[];

      // Import files from manifest
      try {
        // Update progress
        emit(BulkImportInProgress(
          manifestTxId: event.manifestTxId,
          fileIds: files.map((f) => f.id).toList(),
          processedFiles: processedFiles,
          failedFiles: failedPaths,
          currentFileName: files.first.name,
          failedPaths: failedPaths,
          isCreatingFolderHierarchy: true,
        ));

        // Import file
        await _bulkImportFiles(
          driveId: event.driveId,
          parentFolderId: event.parentFolderId,
          files: files,
          onCreateFolderHierarchyStart: () {
            final state = this.state;

            if (state is BulkImportInProgress) {
              emit(state.copyWith(
                isCreatingFolderHierarchy: true,
              ));
            }
          },
          onFileProgress: (fileName) {
            final state = this.state;
            processedFiles++;

            if (state is BulkImportInProgress) {
              emit(state.copyWith(
                currentFileName: fileName,
                processedFiles: processedFiles,
              ));
            }
          },
          onCreateFolderHierarchyEnd: () {
            final state = this.state;

            if (state is BulkImportInProgress) {
              emit(state.copyWith(
                isCreatingFolderHierarchy: false,
              ));
            }
          },
          wallet: _ardriveAuth.currentUser.wallet,
          userCipherKey: _ardriveAuth.currentUser.cipherKey,
        );

        processedFiles++;
      } catch (e) {
        failedPaths.add(files.first.path);
        logger.e('Failed to import file: ${files.first.path}', e);
      }

      final totalFiles = files.length;
      final successfulFiles = processedFiles;
      final failedFiles = failedPaths;

      // Handle result
      if (successfulFiles == 0) {
        // All files failed to import
        emit(const BulkImportError(
          'Failed to import any files. Please check the manifest and try again.',
        ));
      } else {
        // Complete or partial success
        emit(BulkImportSuccess(
          manifestTxId: event.manifestTxId,
          totalFiles: totalFiles,
          successfulFiles: successfulFiles,
          failedFiles: failedFiles.length,
        ));
      }
    } catch (e) {
      logger.e('Error during bulk import', e);
      emit(BulkImportError(
        'An unexpected error occurred during the import process. Please try again.',
        e,
      ));
    }
  }

  void _onCancelBulkImport(
    CancelBulkImport event,
    Emitter<BulkImportState> emit,
  ) {
    emit(const BulkImportInitial());
  }

  void _onResetBulkImport(
    ResetBulkImport event,
    Emitter<BulkImportState> emit,
  ) {
    emit(const BulkImportInitial());
  }
}

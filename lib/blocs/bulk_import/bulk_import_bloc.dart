import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/bulk_import/bulk_import_event.dart';
import 'package:ardrive/blocs/bulk_import/bulk_import_state.dart';
import 'package:ardrive/core/arfs/use_cases/bulk_import_files.dart';
import 'package:ardrive/core/arfs/use_cases/check_folder_conflicts.dart';
import 'package:ardrive/manifests/domain/repositories/manifest_repository.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

/// BLoC for managing the bulk import process.
class BulkImportBloc extends Bloc<BulkImportEvent, BulkImportState> {
  final BulkImportFiles _bulkImportFiles;
  final ManifestRepository _manifestRepository;
  final ArDriveAuth _ardriveAuth;
  final CheckFolderConflicts _checkFolderConflicts;

  // Store files in memory when conflicts are detected
  List<ManifestFileEntry>? _pendingFiles;

  BulkImportBloc({
    required BulkImportFiles bulkImportFiles,
    required ManifestRepository manifestRepository,
    required ArDriveAuth ardriveAuth,
    required CheckFolderConflicts checkFolderConflicts,
  })  : _bulkImportFiles = bulkImportFiles,
        _manifestRepository = manifestRepository,
        _ardriveAuth = ardriveAuth,
        _checkFolderConflicts = checkFolderConflicts,
        super(const BulkImportInitial()) {
    on<StartManifestBulkImport>(_onStartManifestBulkImport);
    on<CancelBulkImport>(_onCancelBulkImport);
    on<ResetBulkImport>(_onResetBulkImport);
    on<ReplaceConflictingFiles>(_onReplaceConflictingFiles);
    on<ConfirmManifestBulkImport>(_onConfirmManifestBulkImport);
  }

  String? _manifestOriginalOwnerAddress;

  Future<void> _onStartManifestBulkImport(
    StartManifestBulkImport event,
    Emitter<BulkImportState> emit,
  ) async {
    try {
      emit(BulkImportLoadingManifest(event.manifestTxId));

      // Get manifest data
      final manifestResult =
          await _manifestRepository.getManifest(event.manifestTxId);

      _manifestOriginalOwnerAddress = manifestResult.ownerAddress;
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
          id: const Uuid().v4(),
          path: path,
          name: path.split('/').last,
          dataTxId: data['id'] as String,
          contentType:
              data['contentType'] as String? ?? 'application/octet-stream',
          size: data['size'] as int? ?? 0,
        );
      }).toList();

      // Check for folder conflicts
      final folderConflicts = await _checkFolderConflicts(
        driveId: event.driveId,
        targetFolderId: event.parentFolderId,
        files: files
            .map((e) => FileConflictCheck(
                  name: e.name,
                  path: e.path,
                  parentFolderId: event.parentFolderId,
                  id: e.id,
                ))
            .toList(),
      );

      final Map<String, FileTreeConflict> conflictsMap = {};

      for (var conflict in folderConflicts.conflicts) {
        conflictsMap[conflict.newFileId] = conflict;
      }

      if (folderConflicts.hasConflicts) {
        final conflicts = folderConflicts.conflicts;
        logger.d('Found ${conflicts.length} conflicts');

        for (var conflict in conflicts) {
          logger.d('Conflict: ${conflict.newFileId}');
          logger.d('Existing file id: ${conflict.existingFileId}');

          final index =
              files.indexWhere((file) => file.id == conflict.newFileId);
          files[index] = files[index].copyWith(
            existingFileId: conflict.existingFileId,
          );
        }

        // Store files in memory for later use
        _pendingFiles = files;

        emit(BulkImportFileConflicts(
          manifestTxId: event.manifestTxId,
          conflicts: conflicts,
        ));
        return;
      }

      emit(BulkImportReviewingManifest(
        manifestTxId: event.manifestTxId,
        files: files,
      ));

      return;
    } catch (e) {
      logger.e('Error during bulk import', e);
      emit(BulkImportError(
        'An unexpected error occurred during the import process. Please try again.',
        e,
      ));
    }
  }

  Future<void> _onConfirmManifestBulkImport(
    ConfirmManifestBulkImport event,
    Emitter<BulkImportState> emit,
  ) async {
    await _importFiles(
      files: event.files,
      driveId: event.driveId,
      parentFolderId: event.parentFolderId,
      manifestTxId: event.manifestTxId,
      emit: emit,
    );
  }

  Future<void> _onReplaceConflictingFiles(
    ReplaceConflictingFiles event,
    Emitter<BulkImportState> emit,
  ) async {
    try {
      if (_pendingFiles == null) {
        emit(const BulkImportError(
          'No files to replace. Please start the import process again.',
        ));
        return;
      }

      emit(BulkImportReviewingManifest(
        manifestTxId: event.manifestTxId,
        files: _pendingFiles!,
      ));
    } catch (e) {
      logger.e('Error during file replacement', e);
      emit(BulkImportError(
        'An unexpected error occurred while replacing files. Please try again.',
        e,
      ));
    }
  }

  Future<void> _importFiles({
    required List<ManifestFileEntry> files,
    required String driveId,
    required String parentFolderId,
    required String manifestTxId,
    required Emitter<BulkImportState> emit,
  }) async {
    var processedFiles = 0;
    final failedPaths = <String>[];

    try {
      emit(BulkImportInProgress(
        manifestTxId: manifestTxId,
        fileIds: files.map((f) => f.id).toList(),
        processedFiles: processedFiles,
        failedFiles: failedPaths,
        currentFileName: files.first.name,
        failedPaths: failedPaths,
        isCreatingFolderHierarchy: true,
      ));

      if (_manifestOriginalOwnerAddress == null) {
        emit(const BulkImportError(
          'Failed to import files. Please try again.',
        ));
        return;
      }

      await _bulkImportFiles(
        driveId: driveId,
        parentFolderId: parentFolderId,
        files: files,
        manifestTxId: manifestTxId,
        originalOwnerAddress: _manifestOriginalOwnerAddress!,
        onCreateFolderHierarchyStart: () {
          final state = this.state;
          if (state is BulkImportInProgress) {
            emit(state.copyWith(isCreatingFolderHierarchy: true));
          }
        },
        onFileProgress: (fileName) {
          final state = this.state;
          if (state is BulkImportInProgress) {
            emit(state.copyWith(
              currentFileName: fileName,
              processedFiles: processedFiles,
            ));
          }
        },
        onFileUploadSuccess: (fileName) {
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
            emit(state.copyWith(isCreatingFolderHierarchy: false));
          }
        },
        wallet: _ardriveAuth.currentUser.wallet,
        userCipherKey: _ardriveAuth.currentUser.cipherKey,
      );
    } catch (e) {
      failedPaths.add(files.first.path);
      logger.e('Failed to import file: ${files.first.path}', e);
    }

    final totalFiles = files.length;
    final successfulFiles = processedFiles;
    final failedFiles = failedPaths;

    if (successfulFiles == 0) {
      emit(const BulkImportError(
        'Failed to import any files. Please check the manifest and try again.',
      ));
    } else {
      emit(BulkImportSuccess(
        manifestTxId: manifestTxId,
        totalFiles: totalFiles,
        successfulFiles: successfulFiles,
        failedFiles: failedFiles.length,
      ));
    }
  }

  void _onCancelBulkImport(
    CancelBulkImport event,
    Emitter<BulkImportState> emit,
  ) {
    _bulkImportFiles.cancel();
    _pendingFiles = null;

    int numberOfFilesImported = 0;

    if (state is BulkImportInProgress) {
      numberOfFilesImported = (state as BulkImportInProgress).processedFiles;
    }

    emit(BulkImportCancelled(numberOfFilesImported: numberOfFilesImported));
  }

  void _onResetBulkImport(
    ResetBulkImport event,
    Emitter<BulkImportState> emit,
  ) {
    _pendingFiles = null;
    _bulkImportFiles.reset();
    emit(const BulkImportInitial());
  }
}

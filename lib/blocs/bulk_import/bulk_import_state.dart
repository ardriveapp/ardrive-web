import 'package:ardrive/core/arfs/use_cases/check_folder_conflicts.dart';
import 'package:equatable/equatable.dart';

/// States for the bulk import process.
abstract class BulkImportState extends Equatable {
  const BulkImportState();

  @override
  List<Object?> get props => [];
}

/// Initial state before any bulk import action
class BulkImportInitial extends BulkImportState {
  const BulkImportInitial();
}

/// State when downloading and parsing manifest data
class BulkImportLoadingManifest extends BulkImportState {
  final String manifestTxId;

  const BulkImportLoadingManifest(this.manifestTxId);

  @override
  List<Object> get props => [manifestTxId];
}

/// State when importing files from manifest
class BulkImportInProgress extends BulkImportState {
  final String manifestTxId;
  final List<String> fileIds;
  final int processedFiles;
  final List<String> failedFiles;
  final String currentFileName;
  final List<String> failedPaths;
  final bool isCreatingFolderHierarchy;

  const BulkImportInProgress({
    required this.manifestTxId,
    required this.fileIds,
    required this.processedFiles,
    required this.failedFiles,
    required this.currentFileName,
    required this.failedPaths,
    required this.isCreatingFolderHierarchy,
  });

  @override
  List<Object> get props => [
        manifestTxId,
        fileIds,
        processedFiles,
        failedFiles,
        currentFileName,
        failedPaths,
        isCreatingFolderHierarchy,
      ];

  // copy with
  BulkImportInProgress copyWith({
    bool? isCreatingFolderHierarchy,
    String? currentFileName,
    int? processedFiles,
  }) {
    return BulkImportInProgress(
      manifestTxId: manifestTxId,
      fileIds: fileIds,
      processedFiles: processedFiles ?? this.processedFiles,
      failedFiles: failedFiles,
      currentFileName: currentFileName ?? this.currentFileName,
      failedPaths: failedPaths,
      isCreatingFolderHierarchy:
          isCreatingFolderHierarchy ?? this.isCreatingFolderHierarchy,
    );
  }

  double get progress => fileIds.isEmpty ? 0 : processedFiles / fileIds.length;
}

/// State when bulk import is completed
class BulkImportSuccess extends BulkImportState {
  final String manifestTxId;
  final int totalFiles;
  final int successfulFiles;
  final int failedFiles;

  const BulkImportSuccess({
    required this.manifestTxId,
    required this.totalFiles,
    required this.successfulFiles,
    required this.failedFiles,
  });

  @override
  List<Object> get props => [
        manifestTxId,
        totalFiles,
        successfulFiles,
        failedFiles,
      ];
}

/// State when bulk import encounters an error
class BulkImportError extends BulkImportState {
  final String message;
  final Object? error;

  const BulkImportError(this.message, [this.error]);

  @override
  List<Object?> get props => [message, error];
}

class BulkImportResolvingPaths extends BulkImportState {
  final int totalPaths;
  final int processedPaths;

  const BulkImportResolvingPaths({
    required this.totalPaths,
    required this.processedPaths,
  });

  @override
  List<Object?> get props => [totalPaths, processedPaths];
}

class BulkImportCreatingFolders extends BulkImportState {
  final int totalFolders;
  final int processedFolders;
  final String currentFolderPath;

  const BulkImportCreatingFolders({
    required this.totalFolders,
    required this.processedFolders,
    required this.currentFolderPath,
  });

  @override
  List<Object?> get props =>
      [totalFolders, processedFolders, currentFolderPath];
}

class BulkImportFileConflicts extends BulkImportState {
  final String manifestTxId;
  final List<FileTreeConflict> conflicts;

  const BulkImportFileConflicts({
    required this.manifestTxId,
    required this.conflicts,
  });

  @override
  List<Object?> get props => [manifestTxId, conflicts];
}

import 'package:ardrive/core/arfs/use_cases/upload_file_metadata.dart';
import 'package:ardrive/core/arfs/use_cases/upload_folder_metadata.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:collection/collection.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';

/// Exception thrown when bulk import fails.
class BulkImportException implements Exception {
  final String message;
  final dynamic originalError;

  BulkImportException(
    this.message, {
    this.originalError,
  });

  @override
  String toString() =>
      'BulkImportException: $message${originalError != null ? '\nOriginal error: $originalError' : ''}';
}

/// Result of a bulk import operation.
class BulkImportResult {
  final List<FileEntry> importedFiles;
  final List<FileImportFailure> failures;

  BulkImportResult({
    required this.importedFiles,
    required this.failures,
  });

  bool get hasFailures => failures.isNotEmpty;
  bool get isSuccess => !hasFailures;
  int get totalFiles => importedFiles.length + failures.length;
  double get successRate => importedFiles.length / totalFiles;
}

/// Represents a failure to import a specific file.
class FileImportFailure {
  final String path;
  final String dataTxId;
  final String error;
  final dynamic originalError;

  FileImportFailure({
    required this.path,
    required this.dataTxId,
    required this.error,
    this.originalError,
  });
}

/// Represents a file entry from a manifest.
class ManifestFileEntry {
  final String id;
  final String? existingFileId;
  final String path;
  final String name;
  final String dataTxId;
  final String contentType;
  final int size;

  ManifestFileEntry({
    required this.id,
    this.existingFileId,
    required this.path,
    required this.name,
    required this.dataTxId,
    required this.contentType,
    required this.size,
  });

  ManifestFileEntry copyWith({
    String? id,
    String? path,
    String? name,
    String? dataTxId,
    String? contentType,
    int? size,
    String? existingFileId,
  }) {
    return ManifestFileEntry(
      id: id ?? this.id,
      path: path ?? this.path,
      name: name ?? this.name,
      dataTxId: dataTxId ?? this.dataTxId,
      contentType: contentType ?? this.contentType,
      size: size ?? this.size,
      existingFileId: existingFileId ?? this.existingFileId,
    );
  }
}

/// Use case for bulk importing files from a manifest.
class BulkImportFiles {
  final UploadFileMetadata _uploadFileMetadata;
  final UploadFolderMetadata _uploadFolderMetadata;
  final DriveDao _driveDao;
  final ArweaveService _arweaveService;

  bool _isCancelled = false;

  BulkImportFiles({
    required UploadFileMetadata uploadFileMetadata,
    required UploadFolderMetadata uploadFolderMetadata,
    required DriveDao driveDao,
    required ArweaveService arweaveService,
  })  : _uploadFileMetadata = uploadFileMetadata,
        _uploadFolderMetadata = uploadFolderMetadata,
        _driveDao = driveDao,
        _arweaveService = arweaveService;

  /// Creates a folder hierarchy based on the file path.
  /// Returns the ID of the deepest folder created.
  Future<String> _createFolderHierarchy(
    String driveId,
    String parentFolderId,
    List<String> pathParts,
    Wallet wallet,
    bool isPrivate,
    SecretKey? driveKey,
  ) async {
    String currentParentId = parentFolderId;

    for (final folderName in pathParts) {
      logger.d('folderName: $folderName');

      // Skip empty folder names and current directory markers
      if (folderName.isEmpty || folderName == '.') continue;

      // Check if folder already exists at this level
      final existingFolders = await _driveDao
          .foldersInFolderWithName(
            driveId: driveId,
            parentFolderId: currentParentId,
            name: folderName,
          )
          .get();

      if (existingFolders.isNotEmpty) {
        // Use existing folder
        currentParentId = existingFolders.first.id;
      } else {
        // Create new folder
        late String newFolderId;
        late String metadataTxId;

        logger.d('creating new folder with name: $folderName');

        await _driveDao.transaction(() async {
          // Create the folder and get its ID
          newFolderId = await _driveDao.createFolder(
            driveId: driveId,
            parentFolderId: currentParentId,
            folderName: folderName,
          );

          // Create and upload the folder entity
          final folderEntity = FolderEntity(
            id: newFolderId,
            driveId: driveId,
            parentFolderId: currentParentId,
            name: folderName,
          );

          try {
            // Upload folder metadata first
            final uploadResult = await _uploadFolderMetadata(
              folderEntity: folderEntity,
              customTags: [],
              isPrivate: isPrivate,
              wallet: wallet,
              driveKey: driveKey,
            );

            metadataTxId = uploadResult.metadataTxId;
            folderEntity.txId = metadataTxId;

            // Insert folder revision after successful upload
            await _driveDao.insertFolderRevision(
              folderEntity.toRevisionCompanion(
                performedAction: RevisionAction.create,
              ),
            );
          } catch (e) {
            logger.e('Failed to upload folder metadata', e);
            rethrow;
          }
        });

        currentParentId = newFolderId;
      }
    }

    return currentParentId;
  }

  /// Imports files from a manifest into the specified drive and folder.
  ///
  /// Takes a [manifest] containing file paths and their data transaction IDs,
  /// along with the target [driveId] and [parentFolderId] where the files
  /// should be imported.
  ///
  /// Returns a [BulkImportResult] containing the successfully imported files
  /// and any failures that occurred during the process.
  ///
  /// Throws [BulkImportException] if the import process fails entirely.
  Future<BulkImportResult> call({
    required String driveId,
    required String parentFolderId,
    required List<ManifestFileEntry> files,
    required Wallet wallet,
    required SecretKey userCipherKey,
    void Function(int total, int processed, String currentPath)?
        onFolderProgress,
    void Function(String fileName)? onFileProgress,
    void Function(String fileName)? onFileUploadSuccess,
    void Function(String path)? onFileFailure,
    void Function()? onCreateFolderHierarchyStart,
    void Function()? onCreateFolderHierarchyEnd,
  }) async {
    final importedFiles = <FileEntry>[];
    final failures = <FileImportFailure>[];
    final folderPathToId = <String, String>{};
    final fileDataTxIdToFile = <String, ManifestFileEntry>{};

    for (final file in files) {
      fileDataTxIdToFile[file.dataTxId] = file;
    }

    logger.d('starting bulk import with ${files.length} files');

    try {
      // Get drive to check if it's private
      final targetDrive =
          await _driveDao.driveById(driveId: driveId).getSingle();
      final isPrivate = targetDrive.isPrivate;

      // Get drive key if private
      SecretKey? driveKey;
      if (isPrivate) {
        driveKey = await _driveDao.getDriveKey(driveId, userCipherKey);
      }

      onCreateFolderHierarchyStart?.call();
      // Phase 1: Extract all unique folder paths that need to be created
      final folderPaths = <String>{};
      for (final file in files) {
        final pathParts = file.path.split('/');
        // Remove filename from path parts
        pathParts.removeLast();

        // Skip folder creation for root files
        if (pathParts.isEmpty ||
            (pathParts.length == 1 && pathParts[0].isEmpty)) {
          continue;
        }

        // Build folder paths for non-root files
        String currentPath = '';
        for (final part in pathParts) {
          if (part.isEmpty || part == '.') continue;
          currentPath = currentPath.isEmpty ? part : '$currentPath/$part';
          folderPaths.add(currentPath);
        }
      }

      // Phase 2: Create all necessary folders
      if (folderPaths.isNotEmpty) {
        // Sort folder paths by depth to ensure parent folders are created first
        final sortedFolderPaths = folderPaths.toList()
          ..sort((a, b) {
            final aDepth = a.split('/').length;
            final bDepth = b.split('/').length;
            if (aDepth != bDepth) {
              return aDepth.compareTo(bDepth);
            }
            return a.compareTo(b);
          });

        // Initialize root folder mapping
        folderPathToId['/'] = parentFolderId;

        // Create folders
        var processedFolders = 0;
        final totalFolders = sortedFolderPaths.length;

        for (final path in sortedFolderPaths) {
          onFolderProgress?.call(totalFolders, processedFolders, path);

          final pathParts = path.split('/');
          final parentPath = pathParts.length > 1
              ? pathParts.sublist(0, pathParts.length - 1).join('/')
              : '/';

          final currentParentId = folderPathToId[parentPath]!;

          try {
            final folderId = await _createFolderHierarchy(
              driveId,
              currentParentId,
              [pathParts.last],
              wallet,
              isPrivate,
              driveKey,
            );
            folderPathToId[path] = folderId;
            processedFolders++;
          } catch (e) {
            logger.e('Failed to create folder: $path', e);
            throw BulkImportException(
              'Failed to create folder: $path',
              originalError: e,
            );
          }
        }

        // Final folder progress update
        onFolderProgress?.call(totalFolders, totalFolders, '');
      }

      onCreateFolderHierarchyEnd?.call();

      // Phase 3: Import all files
      // First, collect all transaction IDs
      final txIds = files.map((f) => f.dataTxId).toList();

      logger.i('Fetching transaction info for ${txIds.length} files');

      // Fetch all transaction details in batches
      final txDetailsStream = _arweaveService.getInfoOfTxsToBePinned(txIds);

      await for (final txDetails in txDetailsStream) {
        if (_isCancelled) {
          throw BulkImportException('Bulk import cancelled');
        }

        final List<FileEntity> fileEntries = [];

        for (final dataTxId in txDetails.keys) {
          try {
            final file = fileDataTxIdToFile[dataTxId]!;
            final pathParts = file.path.split('/');
            final fileName = pathParts.removeLast();
            final parentPath = pathParts.join('/');

            // For root files or files with just a leading slash, use the initial parentFolderId
            final finalParentId = (parentPath.isEmpty ||
                    parentPath == '/' ||
                    pathParts.every((part) => part.isEmpty))
                ? parentFolderId
                : folderPathToId[parentPath]!;

            // Get tx details from the batch results
            final tx = txDetails[file.dataTxId]!;

            final now = DateTime.now();

            logger.d(
                'Creating file entity for file: ${file.name} with file id ${file.id}');

            // Create FileEntity for metadata upload
            if (file.existingFileId != null) {
              logger.d('Reusing file id: ${file.existingFileId}');
            }

            final fileEntity = FileEntity(
              id: file.existingFileId ?? file.id,
              driveId: driveId,
              name: fileName,
              size: int.parse(tx.data.size),
              dataTxId: dataTxId,
              parentFolderId: finalParentId,
              dataContentType: tx.tags
                      .firstWhereOrNull((tag) => tag.name == 'Content-Type')
                      ?.value ??
                  file.contentType,
              lastModifiedDate: now,
            );

            fileEntries.add(fileEntity);
          } catch (e) {
            final file = fileDataTxIdToFile[dataTxId]!;
            logger.e('Failed to get tx details for file: ${file.name}', e);
            onFileFailure?.call(file.path);
            failures.add(FileImportFailure(
              path: file.path,
              dataTxId: file.dataTxId,
              error: e.toString(),
              originalError: e,
            ));
          }
        }

        logger.d('fileEntries: ${fileEntries.length}');

        final worker = WorkerPool<FileEntity>(
          numWorkers: 1,
          maxTasksPerWorker: 5,
          taskQueue: fileEntries,
          onWorkerError: (e) {
            logger.e('Bulk import worker error', e, StackTrace.current);
          },
          execute: (file) async {
            if (_isCancelled) {
              throw BulkImportException('Bulk import cancelled');
            }

            onFileProgress?.call(file.name!);

            final fileEntry = await _importFile(
              driveId: driveId,
              parentFolderId: file.parentFolderId!,
              fileId: file.id!,
              fileName: file.name!,
              dataTxId: file.dataTxId!,
              dataContentType: file.dataContentType!,
              dataSize: file.size!,
              wallet: wallet,
              isPrivate: isPrivate,
            );

            onFileUploadSuccess?.call(file.name!);

            return fileEntry;
          },
        );

        await worker.onAllTasksCompleted;
      }
    } catch (e) {
      throw BulkImportException(
        'Bulk import failed',
        originalError: e,
      );
    }

    return BulkImportResult(
      importedFiles: importedFiles,
      failures: failures,
    );
  }

  Future<FileEntry> _importFile({
    required String driveId,
    required String parentFolderId,
    required String fileId,
    required String fileName,
    required String dataTxId,
    required String dataContentType,
    required int dataSize,
    required Wallet wallet,
    required bool isPrivate,
  }) async {
    final now = DateTime.now();

    // Create FileEntity for metadata upload
    late FileEntity fileEntity;

    final existingFileEntity =
        await _driveDao.fileById(fileId: fileId).getSingleOrNull();

    if (existingFileEntity != null) {
      final file = existingFileEntity.copyWith(
        dataTxId: dataTxId,
        dataContentType: Value(dataContentType),
        size: dataSize,
        lastModifiedDate: now,
      );

      fileEntity = file.asEntity();
    } else {
      fileEntity = FileEntity(
        id: fileId,
        driveId: driveId,
        name: fileName,
        size: dataSize,
        dataTxId: dataTxId,
        parentFolderId: parentFolderId,
        dataContentType: dataContentType,
        lastModifiedDate: now,
      );
    }

    // Upload metadata
    late FileMetadataUploadResult metadataUploadResult;

    try {
      metadataUploadResult = await _uploadFileMetadata(
        fileEntity: fileEntity,
        customTags: [],
        isPrivate: isPrivate,
        wallet: wallet,
      );
    } catch (e) {
      logger.e('Failed to upload metadata for file: $fileName', e);
      throw FileImportFailure(
        path: fileName,
        dataTxId: dataTxId,
        error: 'Failed to upload metadata: ${e.toString()}',
      );
    }
    fileEntity.txId = metadataUploadResult.metadataTxId;

    final isExistingFile =
        await _driveDao.fileById(fileId: fileId).getSingleOrNull();

    if (isExistingFile != null) {
      logger.d('Updating existing file entry');

      _driveDao.insertFileRevision(fileEntity.toRevisionCompanion(
          performedAction: RevisionAction.uploadNewVersion));

      // await _fileRepository.updateFile(fileEntity);
      // await _fileRepository.updateFileRevision(
      //     fileEntity, RevisionAction.uploadNewVersion);
    } else {
      logger.d('Creating new file entry');

      final fileEntry = FileEntriesCompanion.insert(
        id: fileId,
        driveId: driveId,
        name: fileName,
        dataTxId: dataTxId,
        size: dataSize,
        lastModifiedDate: now,
        dataContentType: Value(dataContentType),
        parentFolderId: parentFolderId,
        isHidden: const Value(false),
        dateCreated: Value(now),
        lastUpdated: Value(now),
        path: '',
      );

      await _driveDao.transaction(
        () async {
          await _driveDao.into(_driveDao.fileEntries).insert(fileEntry);

          final revision = FileRevisionsCompanion.insert(
            driveId: driveId,
            fileId: fileId,
            name: fileName,
            parentFolderId: parentFolderId,
            action: RevisionAction.create,
            dateCreated: Value(now),
            lastModifiedDate: now,
            size: dataSize,
            dataTxId: dataTxId,
            dataContentType: Value(dataContentType),
            metadataTxId: metadataUploadResult.metadataTxId,
            isHidden: const Value(false),
          );

          await _driveDao.insertFileRevision(revision);
        },
      );
    }

    late FileEntry createdFile;

    createdFile = await _driveDao.fileById(fileId: fileId).getSingle();

    return createdFile;
  }

  void cancel() {
    _isCancelled = true;
  }

  void reset() {
    _isCancelled = false;
  }
}

class BulkImportFailure {
  final ManifestFileEntry file;
  final String error;

  BulkImportFailure({
    required this.file,
    required this.error,
  });
}

import 'package:ardrive/core/arfs/use_cases/insert_file_metadata.dart';
import 'package:ardrive/core/arfs/use_cases/verify_parent_folder.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:collection/collection.dart';
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
  final String path;
  final String name;
  final String dataTxId;
  final String contentType;
  final int size;

  ManifestFileEntry({
    required this.id,
    required this.path,
    required this.name,
    required this.dataTxId,
    required this.contentType,
    required this.size,
  });
}

/// Use case for bulk importing files from a manifest.
class BulkImportFiles {
  final VerifyParentFolder _verifyParentFolder;
  final InsertFileMetadata _insertFileMetadata;
  final DriveDao _driveDao;
  final ArweaveService _arweaveService;

  BulkImportFiles({
    required VerifyParentFolder verifyParentFolder,
    required InsertFileMetadata insertFileMetadata,
    required DriveDao driveDao,
    required ArweaveService arweaveService,
  })  : _verifyParentFolder = verifyParentFolder,
        _insertFileMetadata = insertFileMetadata,
        _driveDao = driveDao,
        _arweaveService = arweaveService;

  /// Creates a folder hierarchy based on the file path.
  /// Returns the ID of the deepest folder created.
  Future<String> _createFolderHierarchy(
    String driveId,
    String parentFolderId,
    List<String> pathParts,
  ) async {
    String currentParentId = parentFolderId;

    // Get drive to check if it's private
    final targetDrive = await _driveDao.driveById(driveId: driveId).getSingle();

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

        logger.d('creating new folder with name: $folderName');

        await _driveDao.transaction(() async {
          // Create the folder and get its ID
          newFolderId = await _driveDao.createFolder(
            driveId: driveId,
            parentFolderId: currentParentId,
            folderName: folderName,
          );

          // Create and save the folder entity revision
          final folderEntity = FolderEntity(
            id: newFolderId,
            driveId: driveId,
            parentFolderId: currentParentId,
            name: folderName,
          );

          // Note: We don't need to handle the drive key here because
          // we're not uploading the folder metadata to Arweave during bulk import.
          // The folder metadata will be synced later by the sync process.

          await _driveDao.insertFolderRevision(
            folderEntity.toRevisionCompanion(
              performedAction: RevisionAction.create,
            ),
          );
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
    void Function(int total, int processed, String currentPath)?
        onFolderProgress,
    void Function(String fileName)? onFileProgress,
    void Function(String path)? onFileFailure,
    void Function()? onCreateFolderHierarchyStart,
    void Function()? onCreateFolderHierarchyEnd,
  }) async {
    final importedFiles = <FileEntry>[];
    final failures = <FileImportFailure>[];
    final folderPathToId = <String, String>{};

    logger.d('starting bulk import with ${files.length} files');

    try {
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
          final folderName = pathParts.last;
          final parentPath = pathParts.length > 1
              ? pathParts.sublist(0, pathParts.length - 1).join('/')
              : '/';

          final currentParentId = folderPathToId[parentPath]!;

          try {
            // Check if folder already exists
            final existingFolders = await _driveDao
                .foldersInFolderWithName(
                  driveId: driveId,
                  parentFolderId: currentParentId,
                  name: folderName,
                )
                .get();

            if (existingFolders.isNotEmpty) {
              folderPathToId[path] = existingFolders.first.id;
              processedFolders++;
              continue;
            }

            // Create new folder
            late String newFolderId;
            await _driveDao.transaction(() async {
              newFolderId = await _driveDao.createFolder(
                driveId: driveId,
                parentFolderId: currentParentId,
                folderName: folderName,
              );

              final folderEntity = FolderEntity(
                id: newFolderId,
                driveId: driveId,
                parentFolderId: currentParentId,
                name: folderName,
              );

              folderEntity.txId = newFolderId;

              await _driveDao.insertFolderRevision(
                folderEntity.toRevisionCompanion(
                  performedAction: RevisionAction.create,
                ),
              );
            });

            folderPathToId[path] = newFolderId;
            processedFolders++;
          } catch (e) {
            logger.e('Failed to create folder: $path');
            throw BulkImportException(
              'Failed to create folder: $path',
              originalError: e,
            );
          }
        }

        // Final folder progress update
        onFolderProgress?.call(totalFolders, totalFolders, '');

        onCreateFolderHierarchyEnd?.call();

        await Future.delayed(const Duration(milliseconds: 50));
      }

      logger.d('files: ${files.length}');

      // Phase 3: Import all files
      // First, collect all transaction IDs
      final txIds = files.map((f) => f.dataTxId).toList();

      logger.d('txIds: ${txIds.length}');

      logger.i('Fetching transaction info for ${txIds.length} files');

      // Fetch all transaction details in batches
      final txDetails = await _arweaveService.getInfoOfTxsToBePinned(
        txIds,
        onTxInfo: (txs) {
          // logger.d('txs: ${txs.length}');
        },
      );

      for (final file in files) {
        try {
          final pathParts = file.path.split('/');
          final fileName = pathParts.removeLast();
          final parentPath = pathParts.join('/');

          onFileProgress?.call(fileName);

          // For root files or files with just a leading slash, use the initial parentFolderId
          final finalParentId = (parentPath.isEmpty ||
                  parentPath == '/' ||
                  pathParts.every((part) => part.isEmpty))
              ? parentFolderId
              : folderPathToId[parentPath]!;

          // Get tx details from the batch results
          final tx = txDetails[file.dataTxId];

          final fileEntry = await _importFile(
            driveId: driveId,
            parentFolderId: finalParentId,
            fileId: file.id,
            fileName: fileName,
            dataTxId: file.dataTxId,
            dataContentType: tx?.tags
                    .firstWhereOrNull((tag) => tag.name == 'Content-Type')
                    ?.value ??
                file.contentType,
            dataSize: int.parse(tx?.data.size ?? file.size.toString()),
          );

          await Future.delayed(const Duration(milliseconds: 50));

          importedFiles.add(fileEntry);
        } catch (e) {
          onFileFailure?.call(file.path);
          failures.add(FileImportFailure(
            path: file.path,
            dataTxId: file.dataTxId,
            error: e.toString(),
            originalError: e,
          ));
        }
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
  }) async {
    final now = DateTime.now();

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

    late FileEntry createdFile;

    await _driveDao.transaction(() async {
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
        metadataTxId: '',
        isHidden: const Value(false),
      );

      await _driveDao.insertFileRevision(revision);

      createdFile = await _driveDao
          .fileById(driveId: driveId, fileId: fileId)
          .getSingle();
    });

    return createdFile;
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

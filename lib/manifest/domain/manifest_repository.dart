import 'dart:async';

import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/blocs/create_manifest/create_manifest_cubit.dart';
import 'package:ardrive/core/arfs/repository/file_repository.dart';
import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/core/arfs/utils/arfs_revision_status_utils.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/entities/manifest_data.dart';
import 'package:ardrive/manifest/domain/exceptions.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:arweave/arweave.dart';
import 'package:collection/collection.dart';

abstract class ManifestRepository {
  /// Saves the manifest file on the database.
  Future<void> saveManifestOnDatabase({
    required ARFSFileUploadMetadata manifest,
    String? existingManifestFileId,
  });

  Future<String> uploadManifest({
    required ManifestUploadParams params,
    ARNSUndername? undername,
    String? processId,
    Function(CreateManifestUploadProgress)? onProgress,
  });

  Future<IOFile> getManifestFile({
    required FolderEntry parentFolder,
    required String manifestName,
    required FolderNode rootFolderNode,
    required String driveId,
    String? fallbackTxId,
  });

  Future<bool> hasPendingFilesOnTargetFolder({required FolderNode folderNode});

  Future<List<FileEntry>> getManifestFilesInFolder({
    required String folderId,
    required String driveId,
  });

  /// Checks if there is a name conflict with the manifest file.
  /// Returns a tuple with the first value being a boolean indicating if there is a conflict. The second value is the existing manifest file id if there is a conflict.
  Future<(bool, String?)> checkNameConflictAndReturnExistingFileId({
    required String driveId,
    required String parentFolderId,
    required String name,
  });
}

class ManifestRepositoryImpl implements ManifestRepository {
  final DriveDao _driveDao;
  final ArDriveUploader _uploader;
  final FolderRepository _folderRepository;
  final ManifestDataBuilder _builder;
  final ARFSRevisionStatusUtils _versionRevisionStatusUtils;
  final ARNSRepository _arnsRepository;
  final FileRepository _fileRepository;

  ManifestRepositoryImpl(
    this._driveDao,
    this._uploader,
    this._folderRepository,
    this._builder,
    this._versionRevisionStatusUtils,
    this._arnsRepository,
    this._fileRepository,
  );

  @override
  Future<void> saveManifestOnDatabase({
    required ARFSFileUploadMetadata manifest,
    String? existingManifestFileId,
  }) async {
    try {
      final manifestFileEntity = FileEntity(
        size: manifest.size,
        parentFolderId: manifest.parentFolderId,
        name: manifest.name,
        lastModifiedDate: DateTime.now(),
        id: manifest.id,
        driveId: manifest.driveId,
        dataTxId: manifest.dataTxId,
        dataContentType: ContentType.manifest,
        assignedNames:
            manifest.assignedName != null ? [manifest.assignedName!] : null,
        fallbackTxId: manifest.fallbackTxId,
      );

      manifestFileEntity.txId = manifest.metadataTxId!;

      final performedAction = existingManifestFileId == null
          ? RevisionAction.create
          : RevisionAction.uploadNewVersion;

      await _fileRepository.updateFile(manifestFileEntity);
      await _fileRepository.updateFileRevision(
        manifestFileEntity,
        performedAction,
      );
    } catch (e) {
      throw ManifestCreationException(
        'Failed to save manifest on database.',
        error: e,
      );
    }
  }

  @override
  Future<String> uploadManifest({
    required ManifestUploadParams params,
    ARNSUndername? undername,
    String? processId,
    Function(CreateManifestUploadProgress)? onProgress,
  }) async {
    try {
      final completer = Completer<String>();

      final controller = await _uploader.upload(
        file: params.manifestFile,
        args: ARFSUploadMetadataArgs(
          driveId: params.driveId,
          parentFolderId: params.parentFolderId,
          entityId: params.existingManifestFileId,
          isPrivate: false,
          type: params.uploadType,
          privacy: DrivePrivacyTag.public,
          assignedName:
              undername != null ? getLiteralARNSRecordName(undername) : null,
          fallbackTxId: params.fallbackTxId,
        ),
        wallet: params.wallet,
        type: params.uploadType,
      );

      onProgress?.call(CreateManifestUploadProgress.uploadingManifest);

      controller.onDone((tasks) async {
        final task = tasks.first;
        final manifestMetadata = task.content!.first as ARFSFileUploadMetadata;

        await saveManifestOnDatabase(
          manifest: manifestMetadata,
          existingManifestFileId: params.existingManifestFileId,
        );

        if (undername != null && processId != null) {
          onProgress?.call(CreateManifestUploadProgress.assigningArNS);
          final newUndername = ARNSUndername(
            name: undername.name,
            domain: undername.domain,
            record: ARNSRecord(
              transactionId: manifestMetadata.dataTxId!,
              ttlSeconds: undername.record.ttlSeconds,
            ),
          );

          await _arnsRepository.setUndernamesToFile(
            undername: newUndername,
            fileId: manifestMetadata.id,
            uploadNewRevision: false,
            driveId: params.driveId,
            processId: processId,
          );
        }

        onProgress?.call(CreateManifestUploadProgress.completed);

        completer.complete(manifestMetadata.dataTxId);
      });

      controller.onError((err) => completer.completeError(err));

      final result = await completer.future;

      return result;
    } catch (e) {
      throw ManifestCreationException(
        'Failed to upload manifest.',
        error: e,
      );
    }
  }

  @override
  Future<IOFile> getManifestFile({
    required FolderEntry parentFolder,
    required String manifestName,
    required FolderNode rootFolderNode,
    required String driveId,
    String? fallbackTxId,
  }) async {
    try {
      final folderNode = rootFolderNode.searchForFolder(parentFolder.id) ??
          await _driveDao.getFolderTree(driveId, parentFolder.id);

      final arweaveManifest = await _builder.build(
        folderNode: folderNode,
        fallbackTxId: fallbackTxId,
      );

      final manifestFile = await IOFileAdapter().fromData(
        arweaveManifest.jsonData,
        name: manifestName,
        lastModifiedDate: DateTime.now(),
        contentType: ContentType.manifest,
      );

      return manifestFile;
    } catch (e) {
      throw ManifestCreationException(
        'Failed to create manifest file.',
        error: e,
      );
    }
  }

  @override
  Future<bool> hasPendingFilesOnTargetFolder({
    required FolderNode folderNode,
  }) async {
    try {
      return _versionRevisionStatusUtils.hasPendingFilesOnTargetFolder(
        folderNode: folderNode,
      );
    } catch (e) {
      throw ManifestCreationException(
        'Failed to check for pending files on target folder.',
        error: e,
      );
    }
  }

  @override
  Future<(bool, String?)> checkNameConflictAndReturnExistingFileId({
    required String driveId,
    required String parentFolderId,
    required String name,
  }) async {
    try {
      final foldersWithName = await _folderRepository.existingFoldersWithName(
          driveId: driveId, parentFolderId: parentFolderId, name: name);
      final filesWithName = await _folderRepository.existingFilesWithName(
          driveId: driveId, parentFolderId: parentFolderId, name: name);

      final conflictingFiles =
          filesWithName.where((e) => e.dataContentType != ContentType.manifest);

      if (foldersWithName.isNotEmpty || conflictingFiles.isNotEmpty) {
        // Name conflicts with existing file or folder
        // This is an error case, send user back to naming the manifest
        return (true, null);
      }

      /// Might be a case where the user is trying to upload a new version of the manifest
      final existingManifestFileId = filesWithName
          .firstWhereOrNull((e) => e.dataContentType == ContentType.manifest)
          ?.id;

      return (false, existingManifestFileId);
    } catch (e) {
      throw ManifestCreationException(
        'Failed to check for name conflict.',
        error: e,
      );
    }
  }

  @override
  Future<List<FileEntry>> getManifestFilesInFolder(
      {required String folderId, required String driveId}) async {
    final folder = await _driveDao.folderById(folderId: folderId).getSingle();

    return _getManifestFilesInFolder(folder, []);
  }

  Future<List<FileEntry>> _getManifestFilesInFolder(
      FolderEntry folder, List<FileEntry> files) async {
    if (folder.parentFolderId == null) {
      files.addAll(
          await _driveDao.manifestInFolder(parentFolderId: folder.id).get());
      return files;
    }

    final parentFolder = await _driveDao
        .folderById(folderId: folder.parentFolderId!)
        .getSingle();

    files.addAll(
        await _driveDao.manifestInFolder(parentFolderId: folder.id).get());

    return _getManifestFilesInFolder(parentFolder, files);
  }
}

class ManifestUploadParams {
  final IOFile manifestFile;
  final String driveId;
  final String parentFolderId;
  final String? existingManifestFileId;
  final UploadType uploadType;
  final Wallet wallet;
  final String? fallbackTxId;

  ManifestUploadParams({
    required this.manifestFile,
    required this.driveId,
    required this.parentFolderId,
    required this.uploadType,
    this.existingManifestFileId,
    required this.wallet,
    this.fallbackTxId,
  });
}

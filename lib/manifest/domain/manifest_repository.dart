import 'dart:async';

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
import 'package:arweave/arweave.dart';
import 'package:collection/collection.dart';

abstract class ManifestRepository {
  /// Saves the manifest file on the database.
  Future<void> saveManifestOnDatabase({
    required ARFSFileUploadMetadata manifest,
    String? existingManifestFileId,
  });

  Future<void> uploadManifest({
    required ManifestUploadParams params,
  });

  Future<IOFile> getManifestFile({
    required FolderEntry parentFolder,
    required String manifestName,
    required FolderNode rootFolderNode,
    required String driveId,
  });

  Future<bool> hasPendingFilesOnTargetFolder({required FolderNode folderNode});

  Future<bool> checkNameConflict({
    required String driveId,
    required String parentFolderId,
    required String name,
  });

  String? get existingManifestFileId;
}

class ManifestRepositoryImpl implements ManifestRepository {
  final DriveDao _driveDao;
  final ArDriveUploader _uploader;
  final FolderRepository _folderRepository;
  final ManifestDataBuilder _builder;
  final ARFSRevisionStatusUtils _versionRevisionStatusUtils;

  ManifestRepositoryImpl(
    this._driveDao,
    this._uploader,
    this._folderRepository,
    this._builder,
    this._versionRevisionStatusUtils,
  );

  String? _existingManifestFileId;

  @override
  String? get existingManifestFileId => _existingManifestFileId;

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
      );

      manifestFileEntity.txId = manifest.metadataTxId!;

      await _driveDao.runTransaction(
        () async {
          await _driveDao.writeFileEntity(manifestFileEntity);

          await _driveDao.insertFileRevision(
            manifestFileEntity.toRevisionCompanion(
              performedAction: existingManifestFileId == null
                  ? RevisionAction.create
                  : RevisionAction.uploadNewVersion,
            ),
          );
        },
      );
    } catch (e) {
      throw ManifestCreationException(
        'Failed to save manifest on database.',
        error: e,
      );
    }
  }

  @override
  Future<void> uploadManifest({
    required ManifestUploadParams params,
  }) async {
    try {
      final completer = Completer<void>();

      final controller = await _uploader.upload(
        file: params.manifestFile,
        args: ARFSUploadMetadataArgs(
          driveId: params.driveId,
          parentFolderId: params.parentFolderId,
          entityId: params.existingManifestFileId,
          isPrivate: false,
          type: params.uploadType,
          privacy: DrivePrivacyTag.public,
        ),
        wallet: params.wallet,
        type: params.uploadType,
      );

      controller.onDone((tasks) {
        final task = tasks.first;
        final manifestMetadata = task.content!.first as ARFSFileUploadMetadata;

        saveManifestOnDatabase(
          manifest: manifestMetadata,
          existingManifestFileId: existingManifestFileId,
        );

        completer.complete();
      });

      controller.onError((err) => completer.completeError(err));

      await completer.future;
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
  }) async {
    try {
      final folderNode = rootFolderNode.searchForFolder(parentFolder.id) ??
          await _driveDao.getFolderTree(driveId, parentFolder.id);

      final arweaveManifest = await _builder.build(
        folderNode: folderNode,
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
  Future<bool> checkNameConflict({
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
        return true;
      }

      /// Might be a case where the user is trying to upload a new version of the manifest
      _existingManifestFileId = filesWithName
          .firstWhereOrNull((e) => e.dataContentType == ContentType.manifest)
          ?.id;

      return false;
    } catch (e) {
      throw ManifestCreationException(
        'Failed to check for name conflict.',
        error: e,
      );
    }
  }
}

class ManifestUploadParams {
  final IOFile manifestFile;
  final String driveId;
  final String parentFolderId;
  final String? existingManifestFileId;
  final UploadType uploadType;
  final Wallet wallet;

  ManifestUploadParams({
    required this.manifestFile,
    required this.driveId,
    required this.parentFolderId,
    required this.uploadType,
    this.existingManifestFileId,
    required this.wallet,
  });
}

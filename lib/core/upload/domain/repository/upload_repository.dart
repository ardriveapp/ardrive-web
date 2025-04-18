import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/upload/models/upload_file.dart';
import 'package:ardrive/blocs/upload/models/web_folder.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/components/file_picker_modal.dart';
import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/entities/folder_entity.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/models/drive.dart';
import 'package:ardrive/models/enums.dart';
import 'package:ardrive/models/file_revision.dart';
import 'package:ardrive/models/folder_revision.dart';
import 'package:ardrive/services/license/license_service.dart';
import 'package:ardrive/services/license/license_state.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

abstract class UploadRepository {
  Future<UploadController> uploadFiles({
    required List<UploadFile> files,
    required Drive targetDrive,
    required Map<String, String> conflictingFiles,
    LicenseState? licenseStateConfigured,
    required FolderEntry targetFolder,
    required UploadMethod uploadMethod,
    String? assignedName,
    required bool uploadThumbnail,
  });

  Future<UploadController> uploadFolders({
    required List<UploadFile> files,
    required Drive targetDrive,
    required List<String> conflictingFolders,
    required Map<String, String> conflictingFiles,
    LicenseState? licenseStateConfigured,
    required FolderEntry targetFolder,
    required UploadMethod uploadMethod,
    required Map<String, WebFolder> foldersByPath,
    required bool uploadThumbnail,
    // IMPORTANT: This must only apply when uploading a single file inside a folder
    String? assignedName,
  });

  /// Picks files from the file system.
  ///
  /// This method is used to pick files from the file system.
  Future<List<UploadFile>> pickFiles({
    required BuildContext context,
    required String parentFolderId,
  });

  Future<List<UploadFile>> pickFilesFromFolder({
    required BuildContext context,
    required String parentFolderId,
  });

  factory UploadRepository({
    required ArDriveUploader ardriveUploader,
    required DriveDao driveDao,
    required ArDriveAuth auth,
    required LicenseService licenseService,
    required ArDriveIO ardriveIO,
  }) {
    return _UploadRepositoryImpl(
      ardriveUploader: ardriveUploader,
      driveDao: driveDao,
      auth: auth,
      licenseService: licenseService,
      ardriveIO: ardriveIO,
    );
  }
}

class _UploadRepositoryImpl implements UploadRepository {
  final ArDriveUploader _ardriveUploader;
  final DriveDao _driveDao;
  final ArDriveAuth _auth;
  final LicenseService _licenseService;
  final ArDriveIO _ardriveIO;

  _UploadRepositoryImpl({
    required ArDriveUploader ardriveUploader,
    required DriveDao driveDao,
    required ArDriveAuth auth,
    required LicenseService licenseService,
    required ArDriveIO ardriveIO,
  })  : _ardriveUploader = ardriveUploader,
        _driveDao = driveDao,
        _auth = auth,
        _licenseService = licenseService,
        _ardriveIO = ardriveIO;

  @override
  Future<UploadController> uploadFiles({
    required List<UploadFile> files,
    required Drive targetDrive,
    required Map<String, String> conflictingFiles,
    LicenseState? licenseStateConfigured,
    required FolderEntry targetFolder,
    required UploadMethod uploadMethod,
    String? assignedName,
    required bool uploadThumbnail,
  }) async {
    final private = targetDrive.isPrivate;
    final driveKey = private
        ? await _driveDao.getDriveKey(
            targetDrive.id, _auth.currentUser.cipherKey)
        : null;

    List<(ARFSUploadMetadataArgs, IOFile)> uploadFiles = [];
    for (var file in files) {
      final conflictingId = conflictingFiles[file.getIdentifier()];
      final revisionAction = conflictingId != null
          ? RevisionAction.uploadNewVersion
          : RevisionAction.create;

      final licenseStateResolved = licenseStateConfigured ??
          await _licenseStateForFileId(conflictingId, targetDrive.id);

      final args = ARFSUploadMetadataArgs(
        isPrivate: targetDrive.isPrivate,
        driveId: targetDrive.id,
        parentFolderId: targetFolder.id,
        privacy: targetDrive.isPrivate ? 'private' : 'public',
        entityId: revisionAction == RevisionAction.uploadNewVersion
            ? conflictingId
            : null,
        type:
            uploadMethod == UploadMethod.ar ? UploadType.d2n : UploadType.turbo,
        licenseDefinitionTxId: licenseStateResolved?.meta.licenseDefinitionTxId,
        licenseAdditionalTags: licenseStateResolved?.params?.toAdditionalTags(),
        assignedName: assignedName,
      );

      uploadFiles.add((args, file.ioFile));
    }

    /// Creates the uploader and starts the upload.
    final uploadController = await _ardriveUploader.uploadFiles(
      files: uploadFiles,
      wallet: _auth.currentUser.wallet,
      driveKey: driveKey?.key,
      uploadThumbnail: uploadThumbnail,
      type: uploadMethod == UploadMethod.ar ? UploadType.d2n : UploadType.turbo,
    );

    uploadController.onCompleteTask((tasks) {
      _saveTaskToDB(tasks, conflictingFiles, []);
    });

    return uploadController;
  }

  @override
  Future<UploadController> uploadFolders({
    required List<UploadFile> files,
    required Drive targetDrive,
    required Map<String, String> conflictingFiles,
    required List<String> conflictingFolders,
    LicenseState? licenseStateConfigured,
    required FolderEntry targetFolder,
    required UploadMethod uploadMethod,
    required Map<String, WebFolder> foldersByPath,
    required bool uploadThumbnail,
    String? assignedName,
  }) async {
    final private = targetDrive.isPrivate;
    final driveKey = private
        ? await _driveDao.getDriveKey(
            targetDrive.id, _auth.currentUser.cipherKey)
        : null;

    List<(ARFSUploadMetadataArgs, IOEntity)> entities = [];

    for (var folder in foldersByPath.values) {
      final folderMetadata = ARFSUploadMetadataArgs(
        isPrivate: targetDrive.isPrivate,
        driveId: targetDrive.id,
        parentFolderId: folder.parentFolderId,
        privacy: targetDrive.isPrivate ? 'private' : 'public',
        entityId: folder.id,
        type:
            uploadMethod == UploadMethod.ar ? UploadType.d2n : UploadType.turbo,
      );

      entities.add((
        folderMetadata,
        UploadFolder(
          lastModifiedDate: DateTime.now(),
          name: folder.name,
        ),
      ));
    }

    for (var file in files) {
      final fileId = conflictingFiles.containsKey(file.getIdentifier())
          ? conflictingFiles[file.getIdentifier()]
          : null;
      // TODO: We are verifying the conflicting files twice, we should do it only once.
      logger.d(
          'Reusing id? ${conflictingFiles.containsKey(file.getIdentifier())}');

      final licenseStateResolved = licenseStateConfigured ??
          await _licenseStateForFileId(fileId, targetDrive.id);

      final fileMetadata = ARFSUploadMetadataArgs(
        isPrivate: targetDrive.isPrivate,
        driveId: targetDrive.id,
        parentFolderId: file.parentFolderId,
        privacy: targetDrive.isPrivate ? 'private' : 'public',
        entityId: fileId,
        type:
            uploadMethod == UploadMethod.ar ? UploadType.d2n : UploadType.turbo,
        licenseDefinitionTxId: licenseStateResolved?.meta.licenseDefinitionTxId,
        licenseAdditionalTags: licenseStateResolved?.params?.toAdditionalTags(),
        assignedName: assignedName,
      );

      entities.add((fileMetadata, file.ioFile));
    }

    final uploadController = await _ardriveUploader.uploadEntities(
      entities: entities,
      wallet: _auth.currentUser.wallet,
      uploadThumbnail: uploadThumbnail,
      type: uploadMethod == UploadMethod.ar ? UploadType.d2n : UploadType.turbo,
      driveKey: driveKey?.key,
    );

    uploadController.onCompleteTask((task) {
      _saveTaskToDB(task, conflictingFiles, conflictingFolders);
    });

    return uploadController;
  }

  Future<LicenseState?> _licenseStateForFileId(
      String? fileId, String driveId) async {
    if (fileId != null) {
      final latestRevision = await _driveDao
          .latestFileRevisionByFileIdWithLicense(
            driveId: driveId,
            fileId: fileId,
          )
          .getSingleOrNull();
      if (latestRevision?.license != null) {
        final licenseCompanion = latestRevision!.license!.toCompanion(true);
        return _licenseService.fromCompanion(licenseCompanion);
      }
    }
    return null;
  }

  Future<void> _saveTaskToDB(
    UploadTask task,
    Map<String, String> conflictingFiles,
    List<String> conflictingFolders,
  ) async {
    final metadatas = task.content;

    if (metadatas != null) {
      for (var metadata in metadatas) {
        if (metadata is ARFSFileUploadMetadata) {
          final fileMetadata = metadata;

          final revisionAction = conflictingFiles.values.contains(metadata.id)
              ? RevisionAction.uploadNewVersion
              : RevisionAction.create;

          Thumbnail? thumbnail;

          if (fileMetadata.thumbnailInfo != null) {
            thumbnail = Thumbnail(variants: [
              Variant.fromJson(fileMetadata.thumbnailInfo!.first.toJson())
            ]);
          }

          final entity = FileEntity(
            dataContentType: fileMetadata.dataContentType,
            dataTxId: fileMetadata.dataTxId,
            licenseTxId: fileMetadata.licenseTxId,
            driveId: fileMetadata.driveId,
            id: fileMetadata.id,
            lastModifiedDate: fileMetadata.lastModifiedDate,
            name: fileMetadata.name,
            parentFolderId: fileMetadata.parentFolderId,
            size: fileMetadata.size,
            thumbnail: thumbnail,
            assignedNames: fileMetadata.assignedName != null
                ? [fileMetadata.assignedName!]
                : [],
            // TODO: pinnedDataOwnerAddress
          );

          LicensesCompanion? licensesCompanion;
          if (fileMetadata.licenseTxId != null) {
            final licenseType = _licenseService
                .licenseTypeByTxId(fileMetadata.licenseDefinitionTxId!)!;

            final licenseState = LicenseState(
              meta: _licenseService.licenseMetaByType(licenseType),
              params: _licenseService.paramsFromAdditionalTags(
                licenseType: licenseType,
                additionalTags: fileMetadata.licenseAdditionalTags,
              ),
            );
            licensesCompanion = _licenseService.toCompanion(
              licenseState: licenseState,
              dataTxId: fileMetadata.dataTxId!,
              fileId: fileMetadata.id,
              driveId: fileMetadata.driveId,
              licenseTxId: fileMetadata.licenseTxId!,
              licenseTxType: fileMetadata.licenseTxId == fileMetadata.dataTxId
                  ? LicenseTxType.composed
                  : LicenseTxType.assertion,
            );
          }

          if (fileMetadata.metadataTxId == null) {
            logger.e('Metadata tx id is null!');
            throw Exception('Metadata tx id is null');
          }
          entity.txId = fileMetadata.metadataTxId!;

          _driveDao.transaction(() async {
            await _driveDao.writeFileEntity(entity);
            await _driveDao.insertFileRevision(
              entity.toRevisionCompanion(
                performedAction: revisionAction,
              ),
            );
            if (licensesCompanion != null) {
              await _driveDao.insertLicense(licensesCompanion);
            }
          });
        } else if (metadata is ARFSFolderUploadMetatadata) {
          final revisionAction = conflictingFolders.contains(metadata.name)
              ? RevisionAction.uploadNewVersion
              : RevisionAction.create;

          final entity = FolderEntity(
            driveId: metadata.driveId,
            id: metadata.id,
            name: metadata.name,
            parentFolderId: metadata.parentFolderId,
          );

          if (metadata.metadataTxId == null) {
            logger.e('Metadata tx id is null!');
            throw Exception('Metadata tx id is null');
          }

          entity.txId = metadata.metadataTxId!;

          await _driveDao.transaction(() async {
            await _driveDao.createFolder(
              driveId: metadata.driveId,
              parentFolderId: metadata.parentFolderId,
              folderName: metadata.name,
              folderId: metadata.id,
            );
            await _driveDao.insertFolderRevision(
              entity.toRevisionCompanion(
                performedAction: revisionAction,
              ),
            );
          });
        }
      }
    }
  }

  @override
  Future<List<UploadFile>> pickFiles({
    required BuildContext context,
    required String parentFolderId,
  }) async {
    // Display multiple options on Mobile
    // Open file picker on Web
    final ioFiles = kIsWeb
        ? await _ardriveIO.pickFiles(fileSource: FileSource.fileSystem)
        // ignore: use_build_context_synchronously
        : await showMultipleFilesFilePickerModal(context);

    final uploadFiles = ioFiles
        .map((file) => UploadFile(ioFile: file, parentFolderId: parentFolderId))
        .toList();

    return uploadFiles;
  }

  @override
  Future<List<UploadFile>> pickFilesFromFolder(
      {required BuildContext context, required String parentFolderId}) async {
    final ioFolder = await _ardriveIO.pickFolder();
    final ioFiles = await ioFolder.listFiles();

    final isMobilePlatform = AppPlatform.isMobile;
    final shouldUseRelativePath = isMobilePlatform && ioFolder.path.isNotEmpty;
    final relativeTo = shouldUseRelativePath ? getDirname(ioFolder.path) : null;

    final uploadFiles = ioFiles
        .map(
          (file) => UploadFile(
            ioFile: file,
            parentFolderId: parentFolderId,
            relativeTo: relativeTo,
          ),
        )
        .toList();
    return uploadFiles;
  }
}

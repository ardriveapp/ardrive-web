import 'package:ardrive/blocs/upload/upload_file.dart';
import 'package:ardrive/blocs/upload/upload_plan.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/models/drive.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:mime/mime.dart';
import 'package:uuid/uuid.dart';

import '../blocs/upload/data_item_upload_handle.dart';
import '../blocs/upload/file_upload_handle.dart';
import '../entities/file_entity.dart';
import '../models/database/database.dart';
import '../models/enums.dart';
import '../services/crypto/keys.dart';

class UploadPlanUtils {
  UploadPlanUtils({required this.arweave, required this.driveDao});

  final ArweaveService arweave;
  final DriveDao driveDao;
  final _uuid = Uuid();

  Future<UploadPlan> filesToUploadPlan({
    required List<UploadFile> files,
    required SecretKey cipherKey,
    required Wallet wallet,
    required Map<String, String> conflictingFiles,
    required Drive targetDrive,
    required FolderEntry folderEntry,
  }) async {
    final _dataItemUploadHandles = <String, DataItemUploadHandle>{};
    final _v2FileUploadHandles = <String, FileUploadHandle>{};
    for (var file in files) {
      final fileName = file.name;
      final filePath = '${folderEntry.path}/$fileName';
      final fileSize = file.size;
      final fileEntity = FileEntity(
        driveId: targetDrive.id,
        name: fileName,
        size: fileSize,
        lastModifiedDate: file.lastModifiedDate,
        parentFolderId: folderEntry.id,
        dataContentType: lookupMimeType(fileName) ?? 'application/octet-stream',
      );

      // If this file conflicts with one that already exists in the target folder reuse the id of the conflicting file.
      fileEntity.id = conflictingFiles[fileName] ?? _uuid.v4();

      final private = targetDrive.isPrivate;
      final driveKey = private
          ? await driveDao.getDriveKey(targetDrive.id, cipherKey)
          : null;
      final fileKey =
          private ? await deriveFileKey(driveKey!, fileEntity.id!) : null;

      final revisionAction = !conflictingFiles.containsKey(file.name)
          ? RevisionAction.create
          : RevisionAction.uploadNewVersion;

      if (fileSize < bundleSizeLimit) {
        _dataItemUploadHandles[fileEntity.id!] = DataItemUploadHandle(
          entity: fileEntity,
          path: filePath,
          file: file,
          driveKey: driveKey,
          fileKey: fileKey,
          arweave: arweave,
          wallet: wallet,
          revisionAction: revisionAction,
        );
      } else {
        _v2FileUploadHandles[fileEntity.id!] = FileUploadHandle(
          entity: fileEntity,
          path: filePath,
          file: file,
          driveKey: driveKey,
          fileKey: fileKey,
          revisionAction: revisionAction,
        );
      }
    }
    return UploadPlan.create(
      v2FileUploadHandles: _v2FileUploadHandles,
      dataItemUploadHandles: _dataItemUploadHandles,
    );
  }
}

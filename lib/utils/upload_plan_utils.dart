import 'package:ardrive/blocs/upload/upload_file.dart';
import 'package:ardrive/blocs/upload/upload_plan.dart';
import 'package:ardrive/blocs/upload/web_file.dart';
import 'package:ardrive/blocs/upload/web_folder.dart';
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
  UploadPlanUtils({
    required this.arweave,
    required this.driveDao,
  });

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
      final filePath = '${folderEntry.path}/${file.path}';
      final fileSize = file.size;
      final fileEntity = FileEntity(
        driveId: targetDrive.id,
        name: fileName,
        size: fileSize,
        lastModifiedDate: file.lastModifiedDate,
        parentFolderId: file.parentFolderId,
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

  static Map<String, WebFolder> generateFoldersForFiles(List<WebFile> files) {
    final foldersByPath = <String, WebFolder>{};

    // Generate folders
    for (var file in files) {
      final path = file.file.relativePath!;
      final folderPath = path.split('/');
      folderPath.removeLast();
      for (var i = 0; i < folderPath.length; i++) {
        final currentFolder = folderPath.getRange(0, i + 1).join('/');
        if (foldersByPath[currentFolder] == null) {
          final parentFolderPath = folderPath.getRange(0, i).join('/');
          foldersByPath.putIfAbsent(
            currentFolder,
            () => WebFolder(
              name: folderPath[i],
              id: Uuid().v4(),
              parentFolderPath: parentFolderPath,
            ),
          );
        }
      }
    }

    final sortedFolders = foldersByPath.entries.toList()
      ..sort(
          (a, b) => a.key.split('/').length.compareTo(b.key.split('/').length));
    return Map.fromEntries(sortedFolders);
  }
}

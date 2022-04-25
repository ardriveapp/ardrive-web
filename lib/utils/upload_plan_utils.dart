import 'package:ardrive/blocs/upload/models/models.dart';
import 'package:ardrive/blocs/upload/upload_handles/handles.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:mime/mime.dart';
import 'package:uuid/uuid.dart';

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
    required FolderEntry targetFolder,
    Map<String, WebFolder> folders = const {},
  }) async {
    final _fileDataItemUploadHandles = <String, FileDataItemUploadHandle>{};
    final _fileV2UploadHandles = <String, FileV2UploadHandle>{};
    final _folderDataItemUploadHandles = <String, FolderDataItemUploadHandle>{};

    for (var file in files) {
      final fileName = file.name;
      final filePath = '${targetFolder.path}/${file.path}';
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
        _fileDataItemUploadHandles[fileEntity.id!] = FileDataItemUploadHandle(
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
        _fileV2UploadHandles[fileEntity.id!] = FileV2UploadHandle(
          entity: fileEntity,
          path: filePath,
          file: file,
          driveKey: driveKey,
          fileKey: fileKey,
          revisionAction: revisionAction,
        );
      }
    }
    folders.forEach((key, folder) async {
      _folderDataItemUploadHandles.putIfAbsent(
        folder.id,
        () => FolderDataItemUploadHandle(
          folder: folder,
          arweave: arweave,
          wallet: wallet,
          targetDriveId: targetDrive.id,
        ),
      );
    });

    return UploadPlan.create(
      fileV2UploadHandles: _fileV2UploadHandles,
      fileDataItemUploadHandles: _fileDataItemUploadHandles,
      folderDataItemUploadHandles: _folderDataItemUploadHandles,
    );
  }

  ///Returns a sorted list of folders (root folder first) from a list of files
  ///with paths
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

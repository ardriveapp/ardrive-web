import 'package:ardrive/blocs/upload/models/models.dart';
import 'package:ardrive/blocs/upload/upload_handles/handles.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/mime_lookup.dart';
import 'package:ardrive_io/ardrive_io.dart' show getDirname;
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

class UploadPlanUtils {
  UploadPlanUtils({
    required this.arweave,
    required this.driveDao,
  });

  final ArweaveService arweave;
  final DriveDao driveDao;
  final _uuid = const Uuid();

  Future<UploadPlan> filesToUploadPlan({
    required List<UploadFile> files,
    required SecretKey cipherKey,
    required Wallet wallet,
    required Map<String, String> conflictingFiles,
    required Drive targetDrive,
    required FolderEntry targetFolder,
    Map<String, WebFolder> foldersByPath = const {},
  }) async {
    final fileDataItemUploadHandles = <String, FileDataItemUploadHandle>{};
    final fileV2UploadHandles = <String, FileV2UploadHandle>{};
    final folderDataItemUploadHandles = <String, FolderDataItemUploadHandle>{};
    final private = targetDrive.isPrivate;
    final driveKey =
        private ? await driveDao.getDriveKey(targetDrive.id, cipherKey) : null;
    for (var file in files) {
      final fileName = file.ioFile.name;

      // If path is a blob from drag and drop, use file name. Else use the path field from folder upload
      final filePath = '${targetFolder.path}/${file.getIdentifier()}';

      final parentFolderId = foldersByPath[getDirname(file.getIdentifier())];

      final fileSize = await file.ioFile.length;
      final fileEntity = FileEntity(
        driveId: targetDrive.id,
        name: fileName,
        size: fileSize,
        lastModifiedDate: file.ioFile.lastModifiedDate,
        parentFolderId: parentFolderId?.id ?? file.parentFolderId,
        dataContentType: lookupMimeType(fileName) ?? 'application/octet-stream',
      );

      // If this file conflicts with one that already exists in the target folder reuse the id of the conflicting file.
      fileEntity.id = conflictingFiles[file.getIdentifier()] ?? _uuid.v4();

      final fileKey =
          private ? await deriveFileKey(driveKey!, fileEntity.id!) : null;

      final revisionAction = conflictingFiles.containsKey(file.getIdentifier())
          ? RevisionAction.uploadNewVersion
          : RevisionAction.create;

      if (fileSize < bundleSizeLimit) {
        fileDataItemUploadHandles[fileEntity.id!] = FileDataItemUploadHandle(
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
        fileV2UploadHandles[fileEntity.id!] = FileV2UploadHandle(
          entity: fileEntity,
          path: filePath,
          file: file,
          driveKey: driveKey,
          fileKey: fileKey,
          revisionAction: revisionAction,
        );
      }
    }
    foldersByPath.forEach((key, folder) async {
      folderDataItemUploadHandles.putIfAbsent(
        folder.id,
        () => FolderDataItemUploadHandle(
          folder: folder,
          arweave: arweave,
          wallet: wallet,
          targetDriveId: targetDrive.id,
          driveKey: driveKey,
        ),
      );
    });

    return UploadPlan.create(
      fileV2UploadHandles: fileV2UploadHandles,
      fileDataItemUploadHandles: fileDataItemUploadHandles,
      folderDataItemUploadHandles: folderDataItemUploadHandles,
    );
  }

  ///Returns a sorted list of folders (root folder first) from a list of files
  ///with paths
  static Map<String, WebFolder> generateFoldersForFiles(
    List<UploadFile> files,
  ) {
    final foldersByPath = <String, WebFolder>{};

    // Generate folders
    for (var file in files) {
      final relativeTo = file.relativeTo;
      final path = relativeTo != null
          ? file.ioFile.path.replaceFirst('$relativeTo/', '')
          : file.ioFile.path;
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
              id: const Uuid().v4(),
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

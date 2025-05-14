import 'package:ardrive/blocs/upload/limits.dart';
import 'package:ardrive/blocs/upload/models/models.dart';
import 'package:ardrive/blocs/upload/upload_handles/handles.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_io/ardrive_io.dart'
    show getDirname, lookupMimeTypeWithDefaultType;
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

class UploadPlanUtils {
  UploadPlanUtils({
    required this.arweave,
    required this.turboUploadService,
    required this.driveDao,
    required this.crypto,
  });

  final ArweaveService arweave;
  final TurboUploadService turboUploadService;
  final DriveDao driveDao;
  final ArDriveCrypto crypto;
  final _uuid = const Uuid();

  Future<UploadPlan> filesToUploadPlan({
    required List<UploadFile> files,
    required SecretKey cipherKey,
    required Wallet wallet,
    required Map<String, String> conflictingFiles,
    required Drive targetDrive,
    required FolderEntry targetFolder,
    Map<String, WebFolder> foldersByPath = const {},
    bool useTurbo = false,
  }) async {
    logger.i(
      'Creating upload plan for ${files.length} files'
      ' Target drive: ${targetDrive.id}'
      ' Target folder: ${targetFolder.id}'
      ' Use turbo: $useTurbo',
    );

    final fileDataItemUploadHandles = <String, FileDataItemUploadHandle>{};
    final fileV2UploadHandles = <String, FileV2UploadHandle>{};
    final folderDataItemUploadHandles = <String, FolderDataItemUploadHandle>{};
    final private = targetDrive.isPrivate;
    final driveKey =
        private ? await driveDao.getDriveKey(targetDrive.id, cipherKey) : null;
    for (var file in files) {
      final fileName = file.ioFile.name;

      final parentFolderId = foldersByPath[getDirname(file.getIdentifier())];

      final fileSize = await file.ioFile.length;
      final fileEntity = FileEntity(
        driveId: targetDrive.id,
        name: fileName,
        size: fileSize,
        lastModifiedDate: file.ioFile.lastModifiedDate,
        parentFolderId: parentFolderId?.id ?? file.parentFolderId,
        dataContentType: lookupMimeTypeWithDefaultType(fileName),
      );

      // If this file conflicts with one that already exists in the target folder reuse the id of the conflicting file.
      if (conflictingFiles[file.getIdentifier()] != null) {
        logger.i('File already exists in target folder. Reusing id.');
        fileEntity.id = conflictingFiles[file.getIdentifier()];
      } else {
        logger.i('File does not exist in target folder. Creating new id.');
        fileEntity.id = _uuid.v4();
      }

      final fileKey = private
          ? await crypto.deriveFileKey(driveKey!.key, fileEntity.id!)
          : null;

      final revisionAction = conflictingFiles.containsKey(file.getIdentifier())
          ? RevisionAction.uploadNewVersion
          : RevisionAction.create;

      final bundleSizeLimit = getBundleSizeLimit(useTurbo);

      if (fileSize < bundleSizeLimit) {
        fileDataItemUploadHandles[fileEntity.id!] = FileDataItemUploadHandle(
          entity: fileEntity,
          file: file,
          driveKey: driveKey?.key,
          fileKey: fileKey,
          arweave: arweave,
          wallet: wallet,
          revisionAction: revisionAction,
          crypto: crypto,
        );
      } else {
        fileV2UploadHandles[fileEntity.id!] = FileV2UploadHandle(
          entity: fileEntity,
          file: file,
          driveKey: driveKey?.key,
          fileKey: fileKey,
          revisionAction: revisionAction,
          crypto: crypto,
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
          driveKey: driveKey?.key,
        ),
      );
    });

    return UploadPlan.create(
      fileV2UploadHandles: fileV2UploadHandles,
      fileDataItemUploadHandles: fileDataItemUploadHandles,
      folderDataItemUploadHandles: folderDataItemUploadHandles,
      turboUploadService: turboUploadService,
      maxDataItemCount:
          useTurbo ? maxFilesSizePerBundleUsingTurbo : maxFilesPerBundle,
      useTurbo: useTurbo,
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

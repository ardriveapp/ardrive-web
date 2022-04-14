import 'package:ardrive/blocs/upload/upload_handles/upload_handle.dart';
import 'package:ardrive/blocs/upload/models/web_folder.dart';
import 'package:ardrive/entities/folder_entity.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';

class FolderDataItemUploadHandle implements UploadHandle, DataItemHandle {
  final WebFolder folder;
  final DriveID targetDriveId;
  final SecretKey? driveKey;
  final SecretKey? fileKey;

  /// The size of the file before it was encoded/encrypted for upload.
  @override
  int get size => entityTx.data.lengthInBytes;

  /// The size of the file that has been uploaded, not accounting for the file encoding/encryption overhead.
  @override
  int get uploadedSize => (size * uploadProgress).round();

  bool get isPrivate => driveKey != null && fileKey != null;

  @override
  double uploadProgress = 0;

  late DataItem entityTx;

  ArweaveService arweave;
  Wallet wallet;

  FolderDataItemUploadHandle({
    required this.folder,
    required this.arweave,
    required this.wallet,
    required this.targetDriveId,
    this.driveKey,
    this.fileKey,
  });

  Future<void> writeAndSignFolder({
    required String bundledInTxId,
    required DriveDao driveDao,
  }) async {
    await driveDao.transaction(() async {
      await driveDao.createFolder(
        driveId: targetDriveId,
        parentFolderId: folder.parentFolderId,
        folderName: folder.name,
        path: folder.path,
        folderId: folder.id,
      );

      final folderEntity = FolderEntity(
        id: folder.id,
        driveId: targetDriveId,
        parentFolderId: folder.parentFolderId,
        name: folder.name,
      );

      entityTx = await arweave.prepareEntityDataItem(
        folderEntity,
        wallet,
        driveKey,
      );

      await entityTx.sign(wallet);

      folderEntity.txId = entityTx.id;

      await driveDao.insertFolderRevision(
        folderEntity.toRevisionCompanion(
          performedAction: RevisionAction.create,
        ),
      );
    });
  }

  @override
  int get dataItemCount => 1;

  @override
  Future<List<DataItem>> getDataItems() async {
    return [entityTx];
  }
}

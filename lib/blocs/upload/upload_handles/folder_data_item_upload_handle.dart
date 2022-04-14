import 'dart:convert';

import 'package:ardrive/blocs/upload/models/web_folder.dart';
import 'package:ardrive/blocs/upload/upload_handles/upload_handle.dart';
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

  /// The size of the file before it was encoded/encrypted for upload.
  @override
  int get size => jsonEncode(
        FolderEntity(
          id: folder.id,
          driveId: targetDriveId,
          parentFolderId: folder.parentFolderId,
          name: folder.name,
        ).toJson(),
      ).codeUnits.length;

  /// The size of the file that has been uploaded, not accounting for the file encoding/encryption overhead.
  @override
  int get uploadedSize => (size * uploadProgress).round();

  bool get isPrivate => driveKey != null;

  @override
  double uploadProgress = 0;

  late DataItem folderEntityTx;
  late FolderEntity folderEntity;

  ArweaveService arweave;
  Wallet wallet;

  FolderDataItemUploadHandle({
    required this.folder,
    required this.arweave,
    required this.wallet,
    required this.targetDriveId,
    this.driveKey,
  });

  Future<void> prepareAndsignFolderDataItem() async {
    folderEntity = FolderEntity(
      id: folder.id,
      driveId: targetDriveId,
      parentFolderId: folder.parentFolderId,
      name: folder.name,
    );

    folderEntityTx = await arweave.prepareEntityDataItem(
      folderEntity,
      wallet,
      driveKey,
    );
    await folderEntityTx.sign(wallet);
  }

  Future<void> writeFolderToDatabase({
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

      folderEntity.txId = folderEntityTx.id;

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
    await prepareAndsignFolderDataItem();
    return [folderEntityTx];
  }
}

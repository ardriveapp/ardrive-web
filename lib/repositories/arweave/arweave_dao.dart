import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';

import '../entities/entities.dart';
import 'arweave_helpers.dart';

class ArweaveDao {
  Arweave _arweave;

  ArweaveDao(this._arweave);

  Future<Transaction> prepareDriveEntity(
      String driveId, String rootFolderId, Wallet wallet) async {
    final driveEntity = DriveEntity(rootFolderId);

    final driveEntityTx = await _arweave.createTransaction(
      Transaction(data: json.encode(driveEntity.toJson())),
      wallet,
    );

    driveEntityTx.addApplicationTags();
    driveEntityTx.addTag('Drive-Id', driveId);

    await driveEntityTx.sign(wallet);

    return driveEntityTx;
  }

  Future<Transaction> prepareFolderEntity(
    String folderId,
    String driveId,
    String parentFolderId,
    String name,
    Wallet wallet,
  ) async {
    final folderEntity = FolderEntity(name);

    final folderEntityTx = await _arweave.createTransaction(
      Transaction(data: json.encode(folderEntity.toJson())),
      wallet,
    );

    folderEntityTx.addApplicationTags();
    folderEntityTx.addTag('Drive-Id', driveId);
    folderEntityTx.addTag('Folder-Id', folderId);

    if (parentFolderId != null)
      folderEntityTx.addTag('Parent-Folder-Id', parentFolderId);

    await folderEntityTx.sign(wallet);

    return folderEntityTx;
  }

  Future<UploadTransactions> prepareFileUpload(
    String fileId,
    String driveId,
    String parentFolderId,
    String name,
    int fileSize,
    Uint8List fileStream,
    Wallet wallet,
  ) async {
    final fileDataTx = await _arweave.createTransaction(
      Transaction(dataBytes: fileStream),
      wallet,
    );

    await fileDataTx.sign(wallet);

    final fileEntity = FileEntity(name, fileSize, fileDataTx.id);

    final fileEntityTx = await _arweave.createTransaction(
      Transaction(data: json.encode(fileEntity.toJson())),
      wallet,
    );

    fileEntityTx.addApplicationTags();
    fileEntityTx.addTag('Drive-Id', driveId);
    fileEntityTx.addTag('Parent-Folder-Id', parentFolderId);
    fileEntityTx.addTag('File-Id', fileId);

    await fileEntityTx.sign(wallet);

    return UploadTransactions(fileEntityTx, fileDataTx);
  }
}

class UploadTransactions {
  Transaction entityTx;
  Transaction dataTx;

  UploadTransactions(this.entityTx, this.dataTx);
}

import 'dart:convert';

import 'package:ardrive/blocs/upload/models/upload_file.dart';
import 'package:ardrive/blocs/upload/upload_handles/upload_handle.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/upload/transaction_signer.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:pst/pst.dart';

class FileV2UploadHandle implements UploadHandle {
  final FileEntity entity;
  final UploadFile file;
  final String path;
  final SecretKey? driveKey;
  final SecretKey? fileKey;
  final String revisionAction;
  final ArDriveCrypto crypto;

  /// The size of the file before it was encoded/encrypted for upload.
  @override
  int get size => entity.size!;

  /// The size of the file that has been uploaded, not accounting for the file encoding/encryption overhead.
  @override
  int get uploadedSize => (size * uploadProgress).round();

  bool get isPrivate => driveKey != null && fileKey != null;

  @override
  double uploadProgress = 0;

  late Transaction entityTx;
  late Transaction dataTx;

  FileV2UploadHandle({
    required this.entity,
    required this.path,
    required this.file,
    required this.revisionAction,
    required this.crypto,
    this.driveKey,
    this.fileKey,
    this.hasError = false,
  });

  Future<void> writeFileEntityToDatabase({required DriveDao driveDao}) async {
    if (hasError) return;
    await driveDao.transaction(() async {
      await driveDao.writeFileEntity(entity, path);
      await driveDao.insertFileRevision(
        entity.toRevisionCompanion(performedAction: revisionAction),
      );
    });
  }

  Future<void> prepareAndSignTransactions({
    required ArweaveService arweaveService,
    required Wallet wallet,
    required PstService pstService,
  }) async {
    TransactionSigner signer;

    if (wallet is ArConnectWallet) {
      signer = SafeArConnectTransactionSigner(
        arweaveService: arweaveService,
        wallet: wallet,
        crypto: crypto,
        pstService: pstService,
      );
    } else {
      signer = ArweaveTransactionSigner(
        arweaveService: arweaveService,
        wallet: wallet,
        crypto: crypto,
        pstService: pstService,
      );
    }

    final signedItem = await signer.signTransaction(
      isPrivate: isPrivate,
      file: file.ioFile,
      fileKey: fileKey,
      entity: entity,
    );

    dataTx = signedItem.dataTx;
    entityTx = signedItem.entityTx;
    entity.id = signedItem.entity.id;
  }

  int getFileDataSize() {
    return entity.size!;
  }

  int getMetadataJSONSize() {
    final entityFake = FileEntity(
      id: entity.id,
      dataContentType: entity.dataContentType,
      dataTxId: base64Encode(Uint8List(43)),
      driveId: entity.driveId,
      lastModifiedDate: entity.lastModifiedDate,
      name: entity.name,
      parentFolderId: entity.parentFolderId,
      size: entity.size,
    );
    return utf8.encode(json.encode(entityFake)).lengthInBytes;
  }

  void dispose() {
    entityTx.setData(Uint8List(0));
    dataTx.setData(Uint8List(0));
  }

  @override
  bool hasError;
}

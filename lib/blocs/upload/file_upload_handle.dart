import 'dart:convert';

import 'package:ardrive/blocs/upload/upload_handle.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:file_selector/file_selector.dart';
import 'package:moor/moor.dart';
import 'package:package_info_plus/package_info_plus.dart';

class FileUploadHandle implements UploadHandle {
  final FileEntity entity;
  final XFile file;
  final String path;
  final bool isPrivate;
  final SecretKey? driveKey;
  final SecretKey? fileKey;
  final String revisionAction;

  /// The size of the file before it was encoded/encrypted for upload.
  @override
  int get size => entity.size!;

  /// The size of the file that has been uploaded, not accounting for the file encoding/encryption overhead.
  @override
  int get uploadedSize => (size * uploadProgress).round();

  @override
  double uploadProgress = 0;

  late Transaction entityTx;
  late Transaction dataTx;

  ArweaveService arweave;
  DriveDao driveDao;
  Wallet wallet;

  FileUploadHandle({
    required this.entity,
    required this.path,
    required this.file,
    required this.revisionAction,
    required this.isPrivate,
    required this.arweave,
    required this.driveDao,
    required this.wallet,
    this.driveKey,
    this.fileKey,
  });

  Future<void> writeEntityToDatabase() async {
    await driveDao.writeFileEntity(entity, path);
    await driveDao.insertFileRevision(
      entity.toRevisionCompanion(performedAction: revisionAction),
    );
  }

  Future<void> prepareAndSign() async {
    final packageInfo = await PackageInfo.fromPlatform();

    final fileData = await file.readAsBytes();
    dataTx = await arweave.client.transactions.prepare(
      isPrivate
          ? await createEncryptedTransaction(fileData, fileKey!)
          : Transaction.withBlobData(data: fileData),
      wallet,
    );

    dataTx.addApplicationTags(version: packageInfo.version);

    // Don't include the file's Content-Type tag if it is meant to be private.
    if (!isPrivate) {
      dataTx.addTag(
        EntityTag.contentType,
        entity.dataContentType!,
      );
    }

    await dataTx.sign(wallet);

    entity.dataTxId = dataTx.id;
    entityTx = await arweave.prepareEntityTx(entity, wallet, fileKey);
    entity.txId = entityTx.id;
  }

  int getEntityJSONSize() {
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
    return (utf8.encode(json.encode(entityFake)) as Uint8List).lengthInBytes;
  }

  Future<BigInt> estimateV2UploadCost() async {
    return await arweave.getPrice(byteSize: entity.size!) +
        await arweave.getPrice(byteSize: getEntityJSONSize());
  }

  /// Uploads the file, emitting an event whenever the progress is updated.
  Stream<Null> upload(ArweaveService arweave) async* {
    await arweave.postTx(entityTx);

    await for (final upload in arweave.client.transactions.upload(dataTx)) {
      uploadProgress = upload.progress;
      yield null;
    }
  }
}

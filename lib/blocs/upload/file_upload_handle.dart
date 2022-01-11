import 'package:ardrive/blocs/upload/upload_handle.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:file_selector/file_selector.dart';
import 'package:package_info_plus/package_info_plus.dart';

final bundleSizeLimit = 503316480;

class FileUploadHandle implements UploadHandle {
  final FileEntity entity;
  final XFile file;
  final String path;
  final bool isPrivate;
  final SecretKey? driveKey;
  final SecretKey? fileKey;
  @override
  BigInt get cost {
    return (entityTx as Transaction).reward + (dataTx as Transaction).reward;
  }

  Future<bool> isWithInBundleLimits() async {
    return await file.length() < bundleSizeLimit;
  }

  /// The size of the file before it was encoded/encrypted for upload.
  @override
  int get size => entity.size!;

  /// The size of the file that has been uploaded, not accounting for the file encoding/encryption overhead.
  @override
  int get uploadedSize => (size * uploadProgress).round();

  @override
  double uploadProgress = 0;

  TransactionBase? entityTx;
  TransactionBase? dataTx;

  FileUploadHandle({
    required this.entity,
    required this.path,
    required this.file,
    required this.isPrivate,
    this.entityTx,
    this.dataTx,
    this.driveKey,
    this.fileKey,
  });

  Future<void> prepareAndSign({
    required ArweaveService arweave,
    required Wallet wallet,
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();

    final fileData = await file.readAsBytes();
    if (await isWithInBundleLimits()) {
      dataTx = isPrivate
          ? await createEncryptedDataItem(fileData, fileKey!)
          : DataItem.withBlobData(data: fileData);
      dataTx!.setOwner(await wallet.getOwner());
    } else {
      dataTx = await arweave.client.transactions.prepare(
        isPrivate
            ? await createEncryptedTransaction(fileData, fileKey!)
            : Transaction.withBlobData(data: fileData),
        wallet,
      );
    }

    dataTx!.addApplicationTags(version: packageInfo.version);

    // Don't include the file's Content-Type tag if it is meant to be private.
    if (!isPrivate) {
      dataTx!.addTag(
        EntityTag.contentType,
        entity.dataContentType!,
      );
    }

    await dataTx!.sign(wallet);

    entity.dataTxId = dataTx!.id;
    if (await isWithInBundleLimits()) {
      entityTx = await arweave.prepareEntityDataItem(entity, wallet, fileKey);
      final entityDataItem = (entityTx as DataItem?)!;
      final dataDataItem = (dataTx as DataItem?)!;

      await entityDataItem.sign(wallet);
      await dataDataItem.sign(wallet);
    } else {
      entityTx = await arweave.prepareEntityTx(entity, wallet, fileKey);
    }
  }

  Iterable<DataItem> asDataItems() {
    return [entityTx as DataItem, dataTx as DataItem];
  }

  /// Uploads the file, emitting an event whenever the progress is updated.
  Stream<Null> upload(ArweaveService arweave) async* {
    if (entityTx != null) {
      await arweave.postTx(entityTx as Transaction);
    }

    await for (final upload
        in arweave.client.transactions.upload(dataTx as Transaction)) {
      uploadProgress = upload.progress;
      yield null;
    }
  }
}

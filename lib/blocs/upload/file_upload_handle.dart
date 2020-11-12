import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:meta/meta.dart';

class FileUploadHandle {
  final FileEntity entity;
  final String path;

  BigInt get cost {
    if (bundleTx != null) {
      return bundleTx.reward;
    } else {
      return (entityTx as Transaction).reward + (dataTx as Transaction).reward;
    }
  }

  int get uploadSize {
    if (bundleTx != null) {
      return int.parse(bundleTx.dataSize);
    } else {
      return int.parse((entityTx as Transaction).dataSize) +
          int.parse((dataTx as Transaction).dataSize);
    }
  }

  int uploadedSize = 0;

  double get uploadProgress => uploadedSize / uploadSize;

  Transaction bundleTx;

  TransactionBase entityTx;
  TransactionBase dataTx;

  FileUploadHandle({
    @required this.entity,
    @required this.path,
    this.bundleTx,
    this.entityTx,
    this.dataTx,
  });

  /// Uploads the file, emitting an event whenever the progress is updated.
  Stream<Null> upload(ArweaveService arweave) async* {
    if (bundleTx != null) {
      final dataSize = int.parse(bundleTx.dataSize);

      await for (final upload in arweave.client.transactions.upload(bundleTx)) {
        uploadedSize = (dataSize * upload.progress).toInt();
        yield null;
      }
    } else {
      await arweave.postTx(entityTx);

      final entitySize = int.parse((entityTx as Transaction).dataSize);
      uploadedSize = entitySize;

      yield null;

      final dataSize = int.parse((dataTx as Transaction).dataSize);
      await for (final upload in arweave.client.transactions.upload(dataTx)) {
        uploadedSize = entitySize + (dataSize * upload.progress).toInt();
        yield null;
      }
    }
  }
}

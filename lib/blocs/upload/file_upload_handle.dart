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

  /// The size of the file before it was encoded/encrypted for upload.
  int get size => entity.size;

  /// The size of the file that has been uploaded, not accounting for the file encoding/encryption overhead.
  int get uploadedSize => (size * uploadProgress).round();

  double uploadProgress = 0;

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
    if (entityTx != null) {
      await arweave.postTx(entityTx);
    }

    await for (final upload
        in arweave.client.transactions.upload(dataTx ?? bundleTx)) {
      uploadProgress = upload.progress;
      yield null;
    }
  }
}

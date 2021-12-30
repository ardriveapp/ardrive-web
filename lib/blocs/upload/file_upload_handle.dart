import 'package:ardrive/blocs/upload/upload_handle.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';

class FileUploadHandle implements UploadHandle {
  final FileEntity entity;
  final String path;

  @override
  BigInt get cost {
    return (entityTx as Transaction).reward + (dataTx as Transaction).reward;
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
    this.entityTx,
    this.dataTx,
  });

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

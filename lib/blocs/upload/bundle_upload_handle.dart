import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';

class BundleUploadHandle {
  final Transaction bundleTx;
  final List<DataItem> dataItems = [];

  BundleUploadHandle(this.bundleTx);

  BigInt get cost {
    return bundleTx.reward;
  }

  double uploadProgress = 0;

  /// Uploads the file, emitting an event whenever the progress is updated.
  Stream<Null> upload(ArweaveService arweave) async* {
    await for (final upload in arweave.client.transactions.upload(bundleTx)) {
      uploadProgress = upload.progress;
      yield null;
    }
  }
}

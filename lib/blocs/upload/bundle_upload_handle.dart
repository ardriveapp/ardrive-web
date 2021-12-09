import 'package:ardrive/blocs/upload/upload_handle.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';

class BundleUploadHandle implements UploadHandle {
  final Transaction bundleTx;
  List<String> fileNames = [];

  BundleUploadHandle(this.bundleTx, this.size,this.fileNames );

  @override
  BigInt get cost {
    return bundleTx.reward;
  }

  @override
  double uploadProgress = 0;

  /// Uploads the bundle, emitting an event whenever the progress is updated.
  Stream<Null> upload(ArweaveService arweave) async* {
    await for (final upload in arweave.client.transactions.upload(bundleTx)) {
      uploadProgress = upload.progress;
      yield null;
    }
  }

  @override
  int size;

  @override
  int get uploadedSize => (size * uploadProgress).round();
}

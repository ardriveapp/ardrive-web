import 'package:ardrive/blocs/upload/upload_handle.dart';
import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:moor/moor.dart';

class MultiFileUploadHandle implements UploadHandle {
  final List<FileEntity> fileEntities;
  final List<DataItem> dataItems;

  late Transaction bundleTx;

  MultiFileUploadHandle(this.dataItems, this.fileEntities, this.size);

  @override
  BigInt get cost {
    return bundleTx.reward;
  }

  @override
  double uploadProgress = 0;

  Future<void> prepareBundle({
    required ArweaveService arweaveService,
    required PstService pstService,
    required Wallet wallet,
  }) async {
    final dataBundle = DataBundle(items: dataItems);
    // Create bundle tx
    bundleTx = await arweaveService.prepareDataBundleTx(dataBundle, wallet);
    dataItems.clear();

    // Add tips to bundle tx
    final bundleTip = await pstService.getPSTFee(bundleTx.reward);
    bundleTx
      ..addTag(TipType.tagName, TipType.dataUpload)
      ..setTarget(await pstService.getWeightedPstHolder())
      ..setQuantity(bundleTip);
    await bundleTx.sign(wallet);
  }

  /// Uploads the bundle, emitting an event whenever the progress is updated.
  Stream<Null> upload(ArweaveService arweave) async* {
    await for (final upload in arweave.client.transactions.upload(bundleTx)) {
      uploadProgress = upload.progress;
      yield null;
    }
  }

  void dispose() {
    bundleTx.setData(Uint8List(0));
  }

  @override
  int size;

  @override
  int get uploadedSize => (size * uploadProgress).round();
}

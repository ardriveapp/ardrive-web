import 'package:ardrive/blocs/upload/file_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handle.dart';
import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:moor/moor.dart';

class BundleUploadHandle implements UploadHandle {
  final List<FileUploadHandle> dataItemUploadHandles;

  late Transaction bundleTx;
  late List<FileEntity> fileEntities;

  BundleUploadHandle(this.dataItemUploadHandles, this.size) {
    fileEntities = List.from(dataItemUploadHandles.map((e) => e.entity));
  }

  @override
  BigInt get cost {
    return bundleTx.reward;
  }

  int get numberOfFiles => fileEntities.length;

  @override
  double uploadProgress = 0;

  Future<void> prepareBundle({
    required ArweaveService arweaveService,
    required PstService pstService,
    required Wallet wallet,
  }) async {
    final bundle = await DataBundle.fromHandles(handles: dataItemUploadHandles);
    // Create bundle tx
    bundleTx = await arweaveService.prepareDataBundleTxFromBlob(
      bundle.blob,
      wallet,
    );

    // Add tips to bundle tx
    final bundleTip = await pstService.getPSTFee(bundleTx.reward);
    bundleTx
      ..addTag(TipType.tagName, TipType.dataUpload)
      ..setTarget(await pstService.getWeightedPstHolder())
      ..setQuantity(bundleTip);
    await bundleTx.sign(wallet);

    dataItemUploadHandles.forEach((file) async {
      await file.updateBundledInTxId(bundledInTxId: bundleTx.id);
    });
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

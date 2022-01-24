import 'package:ardrive/blocs/upload/data_item_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handle.dart';
import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:moor/moor.dart';

class BundleUploadHandle implements UploadHandle {
  final List<DataItemUploadHandle> dataItemUploadHandles;

  late Transaction bundleTx;
  late List<FileEntity> fileEntities;

  BundleUploadHandle._create({
    required this.dataItemUploadHandles,
    this.size = 0,
  });

  static Future<BundleUploadHandle> create({
    required List<DataItemUploadHandle> dataItemUploadHandles,
  }) async {
    final bundle = BundleUploadHandle._create(
      dataItemUploadHandles: dataItemUploadHandles,
    );
    bundle.size = await bundle.computeBundleSize();
    return bundle;
  }

  BundleUploadHandle(this.dataItemUploadHandles, {this.size = 0}) {
    fileEntities = List.from(dataItemUploadHandles.map((e) => e.entity));
    computeBundleSize();
  }

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
      await file.writeEntityToDatabase(bundledInTxId: bundleTx.id);
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

  Future<BigInt> estimateBundleCost({required ArweaveService arweave}) async {
    return arweave.getPrice(byteSize: await computeBundleSize());
  }

  Future<int> computeBundleSize() async {
    final fileSizes = <int>[];
    for (var item in dataItemUploadHandles) {
      fileSizes.add(await item.estimateDataItemSizes());
    }
    var size = 0;
    // Add data item binary size
    size += fileSizes.reduce((value, element) => value + element);
    // Add data item offset and entry id for each data item
    size += (fileSizes.length * 64);
    // Add bytes that denote number of data items
    size += 32;
    this.size = size;
    return size;
  }

  @override
  int size;

  @override
  int get uploadedSize => (size * uploadProgress).round();
}

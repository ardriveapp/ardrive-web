import 'package:ardrive/blocs/upload/data_item_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handle.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:moor/moor.dart';

class BundleUploadHandle implements UploadHandle {
  final List<DataItemUploadHandle> dataItemUploadHandles;

  late Transaction bundleTx;
  late Iterable<FileEntity> fileEntities;

  BundleUploadHandle._create({
    required this.dataItemUploadHandles,
    this.size = 0,
  }) {
    fileEntities = dataItemUploadHandles.map((item) => item.entity);
  }

  static Future<BundleUploadHandle> create({
    required List<DataItemUploadHandle> dataItemUploadHandles,
  }) async {
    final bundle = BundleUploadHandle._create(
      dataItemUploadHandles: dataItemUploadHandles,
    );

    bundle.size = await bundle.computeBundleSize();
    return bundle;
  }

  BigInt get cost {
    return bundleTx.reward;
  }

  int get numberOfFiles => fileEntities.length;

  @override
  double uploadProgress = 0;

  Future<void> prepareAndSignBundleTransaction({
    required ArweaveService arweaveService,
    required DriveDao driveDao,
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
      await file.writeFileEntityToDatabase(
          bundledInTxId: bundleTx.id, driveDao: driveDao);
    });
  }

  /// Uploads the bundle, emitting an event whenever the progress is updated.
  Stream<Null> upload(ArweaveService arweave) async* {
    await for (final upload in arweave.client.transactions.upload(
      bundleTx,
      maxConcurrentUploadCount: maxConcurrentUploadCount,
    )) {
      uploadProgress = upload.progress;
      yield null;
    }
  }

  void dispose() {
    bundleTx.setData(Uint8List(0));
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

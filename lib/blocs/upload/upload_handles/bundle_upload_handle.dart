import 'package:ardrive/blocs/upload/upload_handles/file_data_item_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handles/folder_data_item_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handles/upload_handle.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:moor/moor.dart';

class BundleUploadHandle implements UploadHandle {
  final List<FileDataItemUploadHandle> fileDataItemUploadHandles;
  final List<FolderDataItemUploadHandle> folderDataItemUploadHandles;

  late Transaction bundleTx;
  late Iterable<FileEntity> fileEntities;

  BundleUploadHandle._create({
    this.fileDataItemUploadHandles = const [],
    this.folderDataItemUploadHandles = const [],
    this.size = 0,
  }) {
    fileEntities = fileDataItemUploadHandles.map((item) => item.entity);
  }

  static Future<BundleUploadHandle> create({
    List<FileDataItemUploadHandle> fileDataItemUploadHandles = const [],
    List<FolderDataItemUploadHandle> folderDataItemUploadHandles = const [],
  }) async {
    final bundle = BundleUploadHandle._create(
      fileDataItemUploadHandles: fileDataItemUploadHandles,
      folderDataItemUploadHandles: folderDataItemUploadHandles,
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
    final bundle = await DataBundle.fromHandles(
      handles: List.castFrom<FileDataItemUploadHandle, DataItemHandle>(
              fileDataItemUploadHandles) +
          List.castFrom<FolderDataItemUploadHandle, DataItemHandle>(
              folderDataItemUploadHandles),
    );
    // Create bundle tx
    bundleTx = await arweaveService.prepareDataBundleTxFromBlob(
      bundle.blob,
      wallet,
    );

    await pstService.addCommunityTipToTx(bundleTx);

    await bundleTx.sign(wallet);

    // Write entities to database
    for (var folder in folderDataItemUploadHandles) {
      await folder.writeFolderToDatabase(driveDao: driveDao);
    }
    for (var file in fileDataItemUploadHandles) {
      await file.writeFileEntityToDatabase(
          bundledInTxId: bundleTx.id, driveDao: driveDao);
    }
  }

  /// Uploads the bundle, emitting an event whenever the progress is updated.

  Stream<double> upload(ArweaveService arweave) async* {
    yield* arweave.client.transactions
        .upload(bundleTx, maxConcurrentUploadCount: maxConcurrentUploadCount)
        .map((upload) {
      uploadProgress = upload.progress;
      return uploadProgress;
    });
  }

  void dispose() {
    bundleTx.setData(Uint8List(0));
  }

  Future<int> computeBundleSize() async {
    final fileSizes = <int>[];
    for (var item in fileDataItemUploadHandles) {
      fileSizes.add(await item.estimateDataItemSizes());
    }
    for (var item in folderDataItemUploadHandles) {
      fileSizes.add(item.size);
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

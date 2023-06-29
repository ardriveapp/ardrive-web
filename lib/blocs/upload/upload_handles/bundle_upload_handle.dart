import 'package:ardrive/blocs/upload/upload_handles/file_data_item_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handles/folder_data_item_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handles/upload_handle.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/foundation.dart';

class BundleUploadHandle implements UploadHandle {
  final List<FileDataItemUploadHandle> fileDataItemUploadHandles;
  final List<FolderDataItemUploadHandle> folderDataItemUploadHandles;
  final bool useTurbo;

  late Transaction bundleTx;
  late DataItem bundleDataItem;
  late String bundleId;
  late Iterable<FileEntity> fileEntities;

  BundleUploadHandle._create({
    this.fileDataItemUploadHandles = const [],
    this.folderDataItemUploadHandles = const [],
    this.useTurbo = false,
    this.size = 0,
    this.hasError = false,
  }) {
    fileEntities = fileDataItemUploadHandles.map((item) => item.entity);
  }

  static Future<BundleUploadHandle> create({
    List<FileDataItemUploadHandle> fileDataItemUploadHandles = const [],
    List<FolderDataItemUploadHandle> folderDataItemUploadHandles = const [],
    required bool useTurbo,
  }) async {
    final bundle = BundleUploadHandle._create(
      fileDataItemUploadHandles: fileDataItemUploadHandles,
      folderDataItemUploadHandles: folderDataItemUploadHandles,
      useTurbo: useTurbo,
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
    required UploadService turboUploadService,
    required PstService pstService,
    required Wallet wallet,
    bool isArConnect = false,
  }) async {
    final bundle = await DataBundle.fromHandles(
      parallelize: !isArConnect,
      handles: List.castFrom<FileDataItemUploadHandle, DataItemHandle>(
              fileDataItemUploadHandles) +
          List.castFrom<FolderDataItemUploadHandle, DataItemHandle>(
              folderDataItemUploadHandles),
    );

    logger.d('Bundle mounted');

    logger.d('Creating bundle transaction');
    if (useTurbo) {
      bundleDataItem = await arweaveService.prepareBundledDataItem(
        bundle,
        wallet,
      );
      bundleId = bundleDataItem.id;
    } else {
      // Create bundle tx
      bundleTx = await arweaveService.prepareDataBundleTxFromBlob(
        bundle.blob,
        wallet,
      );

      bundleId = bundleTx.id;

      logger.d('Bundle transaction created');

      logger.d('Adding tip');

      await pstService.addCommunityTipToTx(bundleTx);

      logger.d('Tip added');

      logger.d('Signing bundle');

      await bundleTx.sign(wallet);

      logger.d('Bundle signed');
    }
  }

  Future<void> writeBundleItemsToDatabase({
    required DriveDao driveDao,
  }) async {
    if (hasError) return;

    logger.d('Writing bundle items to database');

    // Write entities to database
    for (var folder in folderDataItemUploadHandles) {
      await folder.writeFolderToDatabase(driveDao: driveDao);
    }
    for (var file in fileDataItemUploadHandles) {
      await file.writeFileEntityToDatabase(
        bundledInTxId: bundleId,
        driveDao: driveDao,
      );
    }
  }

  /// Uploads the bundle, emitting an event whenever the progress is updated.
  Stream<double> upload(
    ArweaveService arweave,
    UploadService turboUploadService,
  ) async* {
    if (useTurbo) {
      await turboUploadService
          .postDataItem(dataItem: bundleDataItem)
          .onError((error, stackTrace) {
        logger.e(error);
        return hasError = true;
      });
      yield 1;
    } else {
      yield* arweave.client.transactions
          .upload(bundleTx, maxConcurrentUploadCount: maxConcurrentUploadCount)
          .map((upload) {
        uploadProgress = upload.progress;
        return uploadProgress;
      });
    }
  }

  void dispose() {
    if (!useTurbo) {
      bundleTx.setData(Uint8List(0));
    }
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

  @override
  bool hasError;
}

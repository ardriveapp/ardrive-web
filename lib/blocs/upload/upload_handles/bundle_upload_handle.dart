import 'package:ardrive/blocs/upload/upload_handles/file_data_item_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handles/folder_data_item_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handles/upload_handle.dart';
import 'package:ardrive/core/arconnect/safe_arconnect_action.dart';
import 'package:ardrive/core/upload/bundle_signer.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/html/html_util.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/foundation.dart';

class BundleUploadHandle implements UploadHandle {
  final List<FileDataItemUploadHandle> fileDataItemUploadHandles;
  final List<FolderDataItemUploadHandle> folderDataItemUploadHandles;
  late Transaction bundleTx;
  late DataItem bundleDataItem;
  late String bundleId;
  late Iterable<FileEntity> fileEntities;

  BundleUploadHandle._create({
    this.fileDataItemUploadHandles = const [],
    this.folderDataItemUploadHandles = const [],
    this.size = 0,
    this.hasError = false,
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

  void setUploadProgress(double progress) {
    uploadProgress = progress;
  }

  Future<void> prepareAndSignBundleTransaction({
    required ArweaveService arweaveService,
    required TurboUploadService turboUploadService,
    required PstService pstService,
    required Wallet wallet,
    required TabVisibilitySingleton tabVisibilitySingleton,
    bool isArConnect = false,
    bool useTurbo = false,
  }) async {
    logger.d('Preparing bundle');

    late DataBundle bundle;
    try {
      if (isArConnect) {
        bundle = await safeArConnectAction<DataBundle>(
          tabVisibilitySingleton,
          (_) async {
            logger.d('Preparing bundle in safe ArConnect action');
            return DataBundle.fromHandles(
              parallelize: !isArConnect,
              handles: List.castFrom<FileDataItemUploadHandle, DataItemHandle>(
                      fileDataItemUploadHandles) +
                  List.castFrom<FolderDataItemUploadHandle, DataItemHandle>(
                      folderDataItemUploadHandles),
            );
          },
        );
      } else {
        bundle = await DataBundle.fromHandles(
          parallelize: !isArConnect,
          handles: List.castFrom<FileDataItemUploadHandle, DataItemHandle>(
                  fileDataItemUploadHandles) +
              List.castFrom<FolderDataItemUploadHandle, DataItemHandle>(
                  folderDataItemUploadHandles),
        );
      }
    } catch (e) {
      logger.e('Error while preparing bundle: $e');
      hasError = true;
      return;
    }

    logger.d('Bundle mounted');

    logger.d('Creating bundle transaction');
    BundleSigner signer;

    if (useTurbo) {
      if (isArConnect) {
        logger.d('Using ArConnect BDI signer');

        signer = SafeArConnectBDISigner(
          BDISigner(
            arweaveService: arweaveService,
            wallet: wallet,
          ),
        );
      } else {
        signer = BDISigner(
          arweaveService: arweaveService,
          wallet: wallet,
        );
      }

      bundleDataItem = await signer.signBundle(unSignedBundle: bundle);

      bundleId = bundleDataItem.id;
    } else {
      // Create bundle tx
      if (isArConnect) {
        signer = SafeArConnectTransactionSigner(
          ArweaveBundleTransactionSigner(
            arweaveService: arweaveService,
            wallet: wallet,
            pstService: pstService,
          ),
        );
      } else {
        signer = SafeArConnectArweaveBundleTransactionSigner(
          ArweaveBundleTransactionSigner(
            arweaveService: arweaveService,
            wallet: wallet,
            pstService: pstService,
          ),
        );
      }

      bundleTx = await signer.signBundle(unSignedBundle: bundle);

      bundleId = bundleTx.id;
    }
  }

  // TODO: this should not be done here. Implement a new class that handles
  Future<void> writeBundleItemsToDatabase({
    required DriveDao driveDao,
  }) async {
    if (hasError) {
      return;
    }

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

  void clearBundleData({bool useTurbo = false}) {
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

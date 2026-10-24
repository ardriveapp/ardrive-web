import 'dart:typed_data';

import 'package:ardrive/entities/entity.dart' show TransactionUtils;
import 'package:ardrive/publication/domain/publication_files.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart' show EntityTag;
import 'package:arweave/arweave.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// A file a publication adds, before it is signed.
class PublicationItem {
  const PublicationItem({
    required this.name,
    required this.data,
    required this.contentType,
    required this.tags,
  });

  /// Its manifest path, or `manifest` for the manifest.
  final String name;
  final Uint8List data;
  final String contentType;
  final List<PublicationTag> tags;
}

/// Signs and posts a publication's files: plain public data items, never
/// ArFS files in the drive (docs/ArweaveFS.md, "Publication").
///
/// Signing comes first and fixes every ID, so `index.html` can name the
/// social card and the manifest every file before anything is sent. Turbo
/// takes the items one by one, which is how a gateway can serve them the
/// moment they are posted; AR takes them as one bundle, served once it is
/// mined and read, which takes minutes.
class PublicationUploader {
  PublicationUploader({
    required ArweaveService arweave,
    required TurboUploadService turboUploadService,
  })  : _arweave = arweave,
        _turbo = turboUploadService;

  final ArweaveService _arweave;
  final TurboUploadService _turbo;

  Future<DataItem> sign(PublicationItem item, Wallet wallet) async {
    final version = (await PackageInfo.fromPlatform()).version;
    final dataItem = DataItem.withBlobData(data: item.data)
      ..addTag(EntityTag.contentType, item.contentType);
    for (final tag in item.tags) {
      dataItem.addTag(tag.name, tag.value);
    }
    dataItem
      ..addApplicationTags(version: version)
      ..setOwner(await wallet.getOwner());
    await dataItem.sign(ArweaveSigner(wallet));
    return dataItem;
  }

  /// Posts one item to Turbo. Throws what [TurboUploadService] throws, among
  /// them `TurboPaymentRequiredException`.
  Future<void> postToTurbo(DataItem item, Wallet wallet) async {
    logger.i('[publication] posting ${item.id} to Turbo');
    await _turbo.postDataItem(dataItem: item, wallet: wallet);
  }

  /// Posts [items] as one bundle transaction and returns its ID.
  /// [onPosted] runs when the transaction is accepted, before its data is
  /// sent: from then on it is paid for.
  Future<String> postBundle(
    List<DataItem> items,
    Wallet wallet, {
    void Function(String txId)? onPosted,
  }) async {
    final tx = await _arweave.prepareDataBundleTx(
      await DataBundle.fromDataItems(items: items),
      wallet,
    );
    logger.i('[publication] posting bundle ${tx.id} to Arweave');
    await _arweave.uploadTx(
      tx,
      maxConcurrentUploadCount: 1,
      onTransactionPosted: () => onPosted?.call(tx.id),
    );
    return tx.id;
  }
}

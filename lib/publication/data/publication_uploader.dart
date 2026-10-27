import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/entities/entity.dart' show TransactionUtils;
import 'package:ardrive/publication/domain/publication_files.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart' show EntityTag;
import 'package:arweave/arweave.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// How long one publication item may take to post to Turbo. Items are small
/// (the largest, `files.html`, under a megabyte at the 5,000-file cap), so
/// this is generous for a slow connection and short enough to give up on a
/// call that hangs.
const publicationTurboTimeout = Duration(minutes: 2);

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
    this.turboTimeout = publicationTurboTimeout,
  })  : _arweave = arweave,
        _turbo = turboUploadService;

  final ArweaveService _arweave;
  final TurboUploadService _turbo;

  /// How long one item may take to post to Turbo before the publish stops
  /// with Try again, rather than showing "uploading" for ever: the service's
  /// own receive timeout is a year.
  final Duration turboTimeout;

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
  ///
  /// Throws [TimeoutException] after [turboTimeout]. Posting the same signed
  /// item again is safe: Turbo keys an item by its ID.
  Future<void> postToTurbo(DataItem item, Wallet wallet) async {
    logger.i('[publication] posting ${item.id} to Turbo');
    await _turbo
        .postDataItem(dataItem: item, wallet: wallet)
        .timeout(turboTimeout);
  }

  /// [items] as one signed bundle transaction, to post with [uploadBundle].
  Future<Transaction> prepareBundle(
          List<DataItem> items, Wallet wallet) async =>
      _arweave.prepareDataBundleTx(
        await DataBundle.fromDataItems(items: items),
        wallet,
      );

  /// Posts [bundle]. Run again on the same transaction after a failure, it
  /// sends what is missing: a header the network has is answered 208, chunks
  /// are idempotent, and nothing is paid twice. [onPosted] runs when the
  /// header is accepted, from when the transaction is paid for.
  Future<void> uploadBundle(Transaction bundle, {void Function()? onPosted}) {
    logger.i('[publication] posting bundle ${bundle.id} to Arweave');
    return _arweave.uploadTx(
      bundle,
      maxConcurrentUploadCount: 1,
      onTransactionPosted: onPosted,
    );
  }
}

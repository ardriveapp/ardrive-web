import 'dart:typed_data';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Fetches the thumbnail a share link points at, and decrypts it when the
/// recipient has the key for it.
///
/// A v2 link carries `thn`, the transaction id of the file's ArFS thumbnail.
/// For a public file those bytes are a small JPEG anyone can read. For a
/// private file they are encrypted — with the *file* key, the same key the
/// recipient unlocked the page with (`data_bundler.dart`,
/// `createDataItemForThumbnail(encryptionKey: key)` where `key` is
/// `deriveFileKey(driveKey, fileId)`), so a recipient who can open the file can
/// also open its thumbnail. The cipher and IV are public tags on the thumbnail
/// transaction, which costs one `getTransactionDetails` call.
///
/// Every failure here is silent: a thumbnail is a nicety, and a recipient who
/// does not get one sees the type icon instead of an error.
class SharedFileThumbnailLoader {
  SharedFileThumbnailLoader({
    required ArweaveService arweave,
    ArDriveCrypto? crypto,
  })  : _arweave = arweave,
        _crypto = crypto ?? ArDriveCrypto();

  final ArweaveService _arweave;
  final ArDriveCrypto _crypto;

  /// The thumbnail's bytes, or `null` when there will not be any.
  Future<Uint8List?> load({
    required String txId,
    required bool isPrivate,
    SecretKey? fileKey,
  }) async {
    // A private thumbnail without a key is not a fetch that fails; it is one
    // that must not happen. Nothing readable comes back, and the ciphertext of
    // a file the recipient has not unlocked is not this page's to request.
    if (isPrivate && fileKey == null) {
      return null;
    }

    try {
      // The same waterfall the download path uses — primary, then GAR
      // gateways, then arweave.net — so one dead gateway costs nothing.
      //
      // Bounded, and bounded *before* the bytes are buffered rather than after
      // (`fetchDataAtMost`, not `fetchData`): a link is free to point `thn` at
      // any transaction on the network, including a very large one, and this
      // fetch starts on its own the moment the page paints. A size check that
      // runs on `response.bodyBytes` has already paid for every byte it is
      // about to reject.
      final bytes = await _arweave.gatewayFallback.fetchDataAtMost(
        txId,
        _arweave.client,
        maxBytes: thumbnailPreviewMaxFileSize,
      );

      // Either nothing came back, or what came back is too big to be a
      // thumbnail. Both cost the picture and nothing else.
      if (bytes == null) {
        logger.d('No thumbnail of a usable size for tx $txId');

        return null;
      }

      if (!isPrivate) {
        return bytes;
      }

      final transaction = await _arweave.getTransactionDetails(txId);

      if (transaction == null) {
        return null;
      }

      return await _crypto.decryptDataFromTransaction(
        transaction,
        bytes,
        fileKey!,
      );
    } catch (e) {
      logger.d('Could not load the thumbnail for tx $txId: $e');

      return null;
    }
  }
}

/// The file's own thumbnail, with the type icon behind it.
///
/// Shows [fallback] until - and unless - real bytes arrive, so the card never
/// waits on a picture and never shows a broken one.
class SharedFileThumbnail extends StatefulWidget {
  const SharedFileThumbnail({
    super.key,
    required this.txId,
    required this.fallback,
    this.fileKey,
    this.isPrivate = false,
    this.size = 44,
    this.fit = BoxFit.cover,
    this.loader,
    this.semanticLabel,
  });

  /// `thn` from the link.
  final String txId;

  /// Rendered until the bytes arrive, and forever if they never do.
  final Widget fallback;

  /// What the picture is of, for a screen reader. `null` leaves the image
  /// unlabelled, which is the honest answer for a file whose name has not
  /// arrived yet.
  final String? semanticLabel;

  /// The recipient's access key, for a private file's encrypted thumbnail.
  final SecretKey? fileKey;

  final bool isPrivate;

  final double size;

  /// How the picture fills its square. `cover` crops it to a tidy tile, which
  /// is what a 44px avatar beside a name wants; the preview pane wants the
  /// whole picture, so it asks for `contain`.
  final BoxFit fit;

  /// Injectable for tests; otherwise built from the service tree.
  final SharedFileThumbnailLoader? loader;

  @override
  State<SharedFileThumbnail> createState() => _SharedFileThumbnailState();
}

class _SharedFileThumbnailState extends State<SharedFileThumbnail> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SharedFileThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);

    // The same thumbnail is not fetched twice because the card rebuilt; a
    // different one is.
    if (oldWidget.txId != widget.txId ||
        oldWidget.fileKey != widget.fileKey ||
        oldWidget.isPrivate != widget.isPrivate) {
      setState(() => _bytes = null);
      _load();
    }
  }

  void _load() {
    final loader = widget.loader ?? _loaderFromContext();

    if (loader == null) {
      return;
    }

    loader
        .load(
      txId: widget.txId,
      isPrivate: widget.isPrivate,
      fileKey: widget.fileKey,
    )
        .then((bytes) {
      if (!mounted || bytes == null) {
        return;
      }

      setState(() => _bytes = bytes);
    });
  }

  /// `null` when this page is rendered without the app's service tree (widget
  /// tests, and later the standalone viewer). A missing service costs a
  /// thumbnail, never the page.
  SharedFileThumbnailLoader? _loaderFromContext() {
    try {
      return SharedFileThumbnailLoader(arweave: context.read<ArweaveService>());
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;

    if (bytes == null) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(child: widget.fallback),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Image.memory(
          bytes,
          fit: widget.fit,
          filterQuality: FilterQuality.high,
          semanticLabel: widget.semanticLabel,
          errorBuilder: (context, error, stackTrace) =>
              Center(child: widget.fallback),
        ),
      ),
    );
  }
}

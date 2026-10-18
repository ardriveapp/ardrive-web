import 'dart:async';

import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/streamed_upload.dart';
import 'package:ardrive_uploader/src/utils/logger.dart';
import 'package:arweave/arweave.dart';

class D2NStreamedUpload implements StreamedUpload<UploadItem> {
  D2NStreamedUpload({required Arweave Function() getArweave}) : _getArweave = getArweave;

  final Arweave Function() _getArweave;
  UploadAborter? _aborter;

  @override
  Future<StreamedUploadResult> send(
    UploadItem uploadItem,
    Wallet wallet,
    Function(double)? onProgress,
  ) async {
    if (uploadItem is! TransactionUploadItem) {
      throw ArgumentError('handle must be of type TransactionUploadTask');
    }

    /// It is possible to cancel an upload before starting the network request.
    if (_isCanceled) {
      logger.d('Upload canceled on D2NStreamedUpload');
      throw Exception('Upload canceled');
    }

    logger.d('D2NStreamedUpload.send');

    final arweave = _getArweave();
    final transaction = uploadItem.data;

    // A retry sends a transaction that may already be on the network, its
    // header posted: only its chunks are sent then.
    final isKnown = await _isKnownToNetwork(arweave, transaction.id);
    final progressStreamTask = await (isKnown
            ? uploadTransactionChunks(transaction, arweave)
            : uploadTransaction(transaction, arweave))
        .run();
    Completer<StreamedUploadResult> upload = Completer<StreamedUploadResult>();

    progressStreamTask.match((l) {
      // Only posting the header fails before the chunk stream starts.
      upload.complete(StreamedUploadResult(
        success: false,
        error: TransactionHeaderNotPostedException(error: l),
      ));
    }, (uploadProgressAndAborter) async {
      final uploadProgress = uploadProgressAndAborter.$1;
      _aborter = uploadProgressAndAborter.$2;
      final listen = uploadProgress.listen(
        (progress) {
          final uploaded = progress.$1;
          final total = progress.$2;
          final progressPercent = uploaded / total;

          onProgress?.call(progressPercent);
        },
      );

      try {
        await listen.asFuture();

        upload.complete(StreamedUploadResult(success: true));
      } catch (e) {
        logger.i('D2NStreamedUpload.send: error while uploading');
        upload.complete(StreamedUploadResult(success: false, error: e));
      }
    });

    final result = await upload.future;

    return result;
  }

  /// Cancel D2N uploads are not supported yet.
  @override
  Future<void> cancel(UploadItem handle) async {
    logger.i('D2NStreamedUpload.cancel');
    _isCanceled = true;

    await _aborter?.abort();
  }

  bool _isCanceled = false;

  /// Whether the network has [transactionId], pending (202) or mined (200).
  /// Unknown when the lookup fails, which posts the header as for a new
  /// transaction.
  Future<bool> _isKnownToNetwork(Arweave arweave, String transactionId) async {
    try {
      final response = await arweave.api.get('tx/$transactionId/status');
      return response.statusCode == 200 || response.statusCode == 202;
    } catch (e) {
      logger.w('Could not look up transaction $transactionId: $e');
      return false;
    }
  }
}

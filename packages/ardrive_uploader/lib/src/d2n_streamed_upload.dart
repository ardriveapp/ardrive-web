import 'dart:async';

import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/streamed_upload.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/foundation.dart';

class D2NStreamedUpload implements StreamedUpload<UploadItem> {
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
      debugPrint('Upload canceled on D2NStreamedUpload');
      throw Exception('Upload canceled');
    }

    debugPrint('D2NStreamedUpload.send');

    final progressStreamTask = await uploadTransaction((uploadItem).data).run();
    Completer<StreamedUploadResult> upload = Completer<StreamedUploadResult>();

    progressStreamTask.match((l) {
      upload.complete(StreamedUploadResult(success: false));
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
        debugPrint('D2NStreamedUpload.send: error while uploading');
        upload.complete(StreamedUploadResult(success: false));
      }
    });

    final result = await upload.future;

    return result;
  }

  /// Cancel D2N uploads are not supported yet.
  @override
  Future<void> cancel(UploadItem handle) async {
    print('D2NStreamedUpload.cancel');
    _isCanceled = true;

    await _aborter?.abort();
  }

  bool _isCanceled = false;
}

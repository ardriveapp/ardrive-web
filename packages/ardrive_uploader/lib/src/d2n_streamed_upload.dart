import 'dart:async';

import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/streamed_upload.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/foundation.dart';

class D2NStreamedUpload implements StreamedUpload<UploadTask> {
  UploadAborter? _aborter;
  StreamedUploadResult? _result;

  @override
  Future<StreamedUploadResult> send(
    UploadTask handle,
    Wallet wallet,
    UploadController controller,
  ) async {
    if (handle.uploadItem is! TransactionUploadItem) {
      throw ArgumentError('handle must be of type TransactionUploadTask');
    }

    /// It is possible to cancel an upload before starting the network request.
    if (_isCanceled) {
      debugPrint('Upload canceled on D2NStreamedUpload');
      throw Exception('Upload canceled');
    }

    debugPrint('D2NStreamedUpload.send');

    controller.updateProgress(
      task: handle.copyWith(
        progress: 0,
        status: UploadStatus.inProgress,
      ),
    );

    final progressStreamTask = await uploadTransaction(
            (handle.uploadItem as TransactionUploadItem).data)
        .run();
    Completer upload = Completer();

    progressStreamTask.match((l) {
      controller.updateProgress(
        task: handle.copyWith(
          status: UploadStatus.failed,
        ),
      );
    }, (uploadProgressAndAborter) async {
      final uploadProgress = uploadProgressAndAborter.$1;
      _aborter = uploadProgressAndAborter.$2;
      final listen = uploadProgress.listen(
        (progress) {
          final uploaded = progress.$1;
          final total = progress.$2;
          final progressPercent = uploaded / total;

          controller.updateProgress(
            task: handle.copyWith(
              progress: progressPercent,
              status: UploadStatus.inProgress,
            ),
          );

          if (progress.$1 == progress.$2) {
            debugPrint('D2NStreamedUpload.send.onDone');
            // finishes the upload

            controller.updateProgress(
              task: handle.copyWith(
                status: UploadStatus.complete,
                progress: 1,
              ),
            );
          }
        },
        onDone: () {
          _result = StreamedUploadResult(success: true);
        },
        onError: (e) {
          controller.updateProgress(
            task: handle.copyWith(
              status: UploadStatus.failed,
            ),
          );
          _result = StreamedUploadResult(success: false);
        },
      );

      await listen.asFuture();
      upload.complete();
    });

    await upload.future;
    return _result!;
  }

  /// Cancel D2N uploads are not supported yet.
  @override
  Future<void> cancel(UploadTask handle, UploadController controller) async {
    print('D2NStreamedUpload.cancel');
    _isCanceled = true;

    await _aborter?.abort();
  }

  bool _isCanceled = false;
}

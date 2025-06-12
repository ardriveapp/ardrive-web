import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/exceptions.dart';
import 'package:ardrive_uploader/src/streamed_upload.dart';
import 'package:ardrive_uploader/src/turbo_upload_service.dart';
import 'package:ardrive_uploader/src/utils/logger.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/foundation.dart';

class TurboStreamedUpload implements StreamedUpload<UploadItem> {
  @visibleForTesting
  final TurboUploadService service;
  StreamedUploadResult? _result;

  TurboStreamedUpload(this.service);

  @override
  Future<StreamedUploadResult> send(
    uploadItem,
    Wallet wallet,
    Function(double)? onProgress,
  ) async {
    /// It is possible to cancel an upload before starting the network request.
    if (_isCanceled) {
      throw UploadCanceledException(
          'Upload canceled. Cancelling request before sending with TurboStreamedUpload');
    }

    // gets the streamed request
    final streamedRequest = service
        .post(
            wallet: wallet,
            dataItem: uploadItem.data,
            onSendProgress: (progress) {
              onProgress?.call(progress);
            },
            headers:  uploadItem.headers,
            )
        .then((value) async {
      _result = StreamedUploadResult(success: true);
    }).onError((e, s) {
      _result = StreamedUploadResult(success: false, error: e);
    });

    await streamedRequest;

    logger.i(
        'TurboStreamedUpload.send completed with result: ${_result?.success}');

    return _result!;
  }

  @override
  Future<void> cancel(
    UploadItem handle,
  ) async {
    _isCanceled = true;
    await service.cancel();
  }

  bool _isCanceled = false;
}

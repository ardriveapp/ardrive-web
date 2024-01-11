import 'package:arconnect/arconnect.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/exceptions.dart';
import 'package:ardrive_uploader/src/streamed_upload.dart';
import 'package:ardrive_uploader/src/turbo_upload_service_base.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

class TurboStreamedUpload implements StreamedUpload<UploadItem> {
  @visibleForTesting
  final TurboUploadService service;
  final TabVisibilitySingleton _tabVisibility;
  StreamedUploadResult? _result;

  TurboStreamedUpload(
    this.service, {
    TabVisibilitySingleton? tabVisibilitySingleton,
  }) : _tabVisibility = tabVisibilitySingleton ?? TabVisibilitySingleton();

  @override
  Future<StreamedUploadResult> send(
    uploadItem,
    Wallet wallet,
    Function(double)? onProgress,
  ) async {
    final nonce = const Uuid().v4();

    final publicKey = await safeArConnectAction<String>(
      _tabVisibility,
      (_) async {
        return wallet.getOwner();
      },
    );

    final signature = await safeArConnectAction<String>(
      _tabVisibility,
      (_) async {
        return signNonceAndData(
          nonce: nonce,
          wallet: wallet,
        );
      },
    );

    int size = 0;

    final task = uploadItem.data as DataItemResult;

    await for (final data in task.streamGenerator()) {
      size += data.length;
    }

    /// It is possible to cancel an upload before starting the network request.
    if (_isCanceled) {
      throw UploadCanceledException(
          'Upload canceled. Cancelling request before sending with TurboStreamedUpload');
    }

    // gets the streamed request
    final streamedRequest = service
        .postStream(
            wallet: wallet,
            headers: {
              'x-nonce': nonce,
              'x-address': publicKey,
              'x-signature': signature,
            },
            dataItem: uploadItem.data,
            size: size,
            onSendProgress: (progress) {
              onProgress?.call(progress);
            })
        .then((value) async {
      _result = StreamedUploadResult(success: true);

      return value;
    }).onError((e, s) {
      debugPrint('Error on TurboStreamedUpload.send: $e');

      _result = StreamedUploadResult(success: false, error: e);
    });

    await streamedRequest;

    debugPrint(
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

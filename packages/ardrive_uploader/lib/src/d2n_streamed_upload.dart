import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/streamed_upload.dart';
import 'package:arweave/arweave.dart';

class D2NStreamedUpload implements StreamedUpload<UploadTask, dynamic> {
  UploadAborter? _aborter;

  @override
  Future<dynamic> send(
    UploadTask handle,
    Wallet wallet,
    UploadController controller,
  ) async {
    if (handle.uploadItem is! BundleTransactionUploadItem) {
      throw ArgumentError('handle must be of type TransactionUploadTask');
    }

    /// It is possible to cancel an upload before starting the network request.
    if (_isCanceled) {
      print('Upload canceled on D2NStreamedUpload');
      return;
    }

    print('D2NStreamedUpload.send');

    handle = handle.copyWith(
      progress: 0,
      status: UploadStatus.inProgress,
    );

    controller.updateProgress(task: handle);

    final progressStreamTask = await uploadTransaction(
            (handle.uploadItem as BundleTransactionUploadItem).data)
        .run();

    progressStreamTask.match((l) {
      handle = handle.copyWith(status: UploadStatus.failed);
      controller.updateProgress(task: handle);
    }, (uploadProgressAndAborter) async {
      final uploadProgress = uploadProgressAndAborter.$1;
      _aborter = uploadProgressAndAborter.$2;
      final listen = uploadProgress.listen(
        (progress) {
          final uploaded = progress.$1;
          final total = progress.$2;
          final progressPercent = uploaded / total;

          handle = handle.copyWith(
            progress: progressPercent,
            status: UploadStatus.inProgress,
          );

          controller.updateProgress(task: handle);

          if (progress.$1 == progress.$2) {
            print('D2NStreamedUpload.send.onDone');
            // finishes the upload
            handle = handle.copyWith(
              status: UploadStatus.complete,
              progress: 1,
            );

            controller.updateProgress(task: handle);
          }
        },
        onDone: () {
          print('D2NStreamedUpload.send.onDone');
          // finishes the upload
          handle = handle.copyWith(
            status: UploadStatus.complete,
            progress: 1,
          );

          controller.updateProgress(task: handle);
        },
        onError: (e) {
          print('D2NStreamedUpload.send.onError: $e');
          handle = handle.copyWith(
            status: UploadStatus.failed,
          );
          controller.updateProgress(task: handle);
        },
      );

      listen.asFuture();
    });
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

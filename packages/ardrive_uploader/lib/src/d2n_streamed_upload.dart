import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/streamed_upload.dart';
import 'package:arweave/arweave.dart';

class D2NStreamedUpload implements StreamedUpload<UploadTask, dynamic> {
  @override
  Future<dynamic> send(
    UploadTask handle,
    Wallet wallet,
    UploadController controller,
  ) async {
    if (handle.uploadItem is! BundleTransactionUploadItem) {
      throw ArgumentError('handle must be of type TransactionUploadTask');
    }

    print('D2NStreamedUpload.send');

    handle = handle.copyWith(status: UploadStatus.inProgress);

    controller.updateProgress(task: handle);

    final progressStreamTask = await uploadTransaction(
            (handle.uploadItem as BundleTransactionUploadItem).data)
        .run();

    progressStreamTask.match((l) => print(''), (progressStream) async {
      final listen = progressStream.listen(
        (progress) {
          // updates the progress. progress.$1 is the current chunk, progress.$2 is the total chunks
          handle.progress = (progress.$1 / progress.$2);
          controller.updateProgress(task: handle);
        },
        onDone: () {
          // finishes the upload
          handle = handle.copyWith(
              status: UploadStatus.complete, progressInPercentage: 1);

          controller.updateProgress(task: handle);
        },
        onError: (e) {
          handle = handle.copyWith(
            status: UploadStatus.failed,
          );
          controller.updateProgress(task: handle);
        },
      );

      listen.asFuture();
    });
  }
}

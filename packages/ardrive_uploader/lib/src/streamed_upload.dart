import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:arweave/arweave.dart';

class StreamedUploadResult {
  final bool success;

  StreamedUploadResult({
    required this.success,
  });
}

abstract class StreamedUpload<T extends UploadItem> {
  Future<StreamedUploadResult> send(
    T handle,
    Wallet wallet,
    void Function(double)? onProgress,
  );

  Future<void> cancel(T handle);
}

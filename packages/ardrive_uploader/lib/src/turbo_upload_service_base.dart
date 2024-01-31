import 'package:arweave/arweave.dart';

export 'package:ardrive_uploader/src/turbo_streamed_stream_upload_io.dart'
    if (dart.library.html) 'package:ardrive_uploader/src/turbo_streamed_stream_upload_web.dart';
export 'package:ardrive_uploader/src/turbo_streamed_chunked_upload.dart';

abstract class TurboUploadService<T> {
  Future<T> postStream({
    required DataItemResult dataItem,
    required Wallet wallet,
    Function(double p1)? onSendProgress,
    required int size,
    required Map<String, dynamic> headers,
  });

  Future<void> cancel();
}

import 'package:arweave/arweave.dart';

export 'package:ardrive_uploader/src/turbo_upload_service_dart_io.dart'
    if (dart.library.html) 'package:ardrive_uploader/src/turbo_upload_service_web.dart';

abstract class TurboUploadService<T> {
  Future<T> post({
    required DataItemResult dataItem,
    required Wallet wallet,
    Function(double)? onSendProgress,
    Map<String, dynamic>? headers,
  });

  abstract final Uri turboUploadUri;

  Future<void> cancel();
}

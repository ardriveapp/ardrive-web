import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/d2n_streamed_upload.dart';
import 'package:ardrive_uploader/src/turbo_streamed_upload.dart';
import 'package:ardrive_uploader/src/turbo_upload_service_base.dart';
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

class StreamedUploadFactory {
  final Uri turboUploadUri;

  StreamedUploadFactory({
    required this.turboUploadUri,
  });

  StreamedUpload fromUploadType(
    UploadType type,
  ) {
    if (type == UploadType.d2n) {
      return D2NStreamedUpload();
    } else if (type == UploadType.turbo) {
      return TurboStreamedUpload(
        TurboUploadServiceImpl(
          turboUploadUri: turboUploadUri,
        ),
      );
    } else {
      throw Exception('Invalid upload type');
    }
  }
}

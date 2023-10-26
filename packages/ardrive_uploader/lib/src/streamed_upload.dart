import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/d2n_streamed_upload.dart';
import 'package:ardrive_uploader/src/turbo_streamed_upload.dart';
import 'package:ardrive_uploader/src/turbo_upload_service_base.dart';
import 'package:arweave/arweave.dart';

abstract class StreamedUpload<T, R> {
  Future<R> send(
    T handle,
    Wallet wallet,
    UploadController controller,
  );

  Future<void> cancel(T handle, UploadController controller);
}

class StreamedUploadFactory {
  StreamedUpload fromUploadType(
    UploadType type,
    Uri turboUploadUri,
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

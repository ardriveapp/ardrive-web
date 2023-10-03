import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:arweave/arweave.dart';

abstract class StreamedUpload<T, R> {
  Future<R> send(
    T handle,
    Wallet wallet,
    UploadController controller,
  );
}

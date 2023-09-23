import 'package:ardrive_uploader/src/upload_controller.dart';
import 'package:arweave/arweave.dart';

export 'package:ardrive_uploader/src/turbo_upload_service_dart_io.dart'
    if (dart.library.html) 'package:ardrive_uploader/src/turbo_upload_service_web.dart';

abstract class TurboUploadService {
  Future<dynamic> postStream({
    required DataItemResult dataItem,
    required Wallet wallet,
    Function(double p1)? onSendProgress,
    required int size,
    required Map<String, dynamic> headers,
    required UploadController controller,
  });

  bool get isPossibleGetProgress;
}

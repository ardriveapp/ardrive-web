import 'package:ardrive_io/ardrive_io.dart';
import 'package:permission_handler/permission_handler.dart';

/// Request permissions related to storage on `Android` and `iOS`
Future<void> requestPermissions() async {
  await Permission.storage.request();
}

Future<void> verifyPermissions() async {
  if (await Permission.storage.isGranted) {
    return;
  }

  throw FileSystemPermissionDeniedException([Permission.storage]);
}

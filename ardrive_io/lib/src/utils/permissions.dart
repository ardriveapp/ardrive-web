import 'package:ardrive_io/ardrive_io.dart';
import 'package:permission_handler/permission_handler.dart';

/// Request permissions related to storage on `Android` and `iOS`
Future<void> requestPermissions() async {
  await Permission.storage.request();
  await Permission.manageExternalStorage.request();
}

Future<void> verifyPermissions() async {
  List<Permission> deniedPErmissions = [];
  if (await Permission.storage.isGranted) {
    return;
  } else {
    deniedPErmissions.add(Permission.storage);
  }
  if (await Permission.manageExternalStorage.isGranted) {
    return;
  } else {
    deniedPErmissions.add(Permission.manageExternalStorage);
  }

  throw FileSystemPermissionDeniedException(deniedPErmissions);
}

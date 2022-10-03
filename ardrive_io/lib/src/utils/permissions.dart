import 'package:ardrive_io/ardrive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Request permissions related to storage on `Android` and `iOS`
Future<void> requestPermissions() async {
  await Permission.storage.request();
  await Permission.manageExternalStorage.request();
}

Future<void> verifyPermissions() async {
  List<Permission> deniedPermissions = [];
  if (await Permission.storage.isGranted) {
    return;
  } else {
    deniedPermissions.add(Permission.storage);
  }
  if (await Permission.manageExternalStorage.isGranted) {
    return;
  } else {
    deniedPermissions.add(Permission.manageExternalStorage);
  }

  throw FileSystemPermissionDeniedException(deniedPermissions);
}

Future<void> verifyStoragePermission() async {
  if (kIsWeb) {
    return;
  }

  final status = await Permission.storage.request();
  if (status != PermissionStatus.granted) {
    throw FileSystemPermissionDeniedException([Permission.storage]);
  }
}

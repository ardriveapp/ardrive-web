import 'dart:io';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:security_scoped_resource/security_scoped_resource.dart';

/// Request permissions related to storage on `Android` and `iOS`
Future<void> requestPermissions() async {
  await Permission.storage.request();
  await Permission.manageExternalStorage.request();
}

Future<void> verifyPermissions() async {
  if (await shouldSkipStoragePermissionCheck()) {
    return;
  }

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
  if (await shouldSkipStoragePermissionCheck()) {
    return;
  }

  final status = await Permission.storage.request();
  if (status != PermissionStatus.granted) {
    throw FileSystemPermissionDeniedException([Permission.storage]);
  }
}

/// Runs an action in the security scoped resource.
/// When action ends the security scoped ended as well.
///
/// Include in `action` all operations needed in the given `directory`.
///
/// It only applies to iOS, where we need special permissions to pick folders outside our app directory.
Future<T> secureScopedAction<T>(
    Future<T> Function(Directory folder) action, Directory directory) async {
  if (kIsWeb || !Platform.isIOS) {
    return action(directory);
  }

  await SecurityScopedResource.instance
      .startAccessingSecurityScopedResource(directory);

  T value = await action(directory);

  await SecurityScopedResource.instance
      .stopAccessingSecurityScopedResource(directory);

  return value;
}

Future<bool> shouldSkipStoragePermissionCheck() async {
  if (kIsWeb) {
    return true;
  }

  // Android SDK >= 33
  if (Platform.isAndroid) {
    final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
    final AndroidDeviceInfo deviceInfo = await deviceInfoPlugin.androidInfo;

    return (deviceInfo.version.sdkInt) >= 33;
  }

  return false;
}

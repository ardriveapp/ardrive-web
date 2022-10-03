import 'dart:io';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:security_scoped_resource/security_scoped_resource.dart';

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

/// Runs an action in the security scoped resource.
/// When action ends the security scoped ended as well.
///
/// Include in `action` all operations needed in the given `directory`.
///
/// It only applies to iOS, where we need special permissions to pick folders outside our app directory.
Future<T> secureScopedAction<T>(Future<T> action, Directory directory) async {
  if (Platform.isIOS) {
    await SecurityScopedResource.instance
        .startAccessingSecurityScopedResource(directory);
  }

  T value = await action;

  if (Platform.isIOS) {
    await SecurityScopedResource.instance
        .stopAccessingSecurityScopedResource(directory);
  }

  return value;
}

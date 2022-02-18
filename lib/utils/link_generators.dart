import 'package:ardrive/models/models.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

Future<Uri> generateDriveShareLink({
  required Drive drive,
  SecretKey? driveKey,
}) async {
  // On web, link to the current origin the user is on.
  // Elsewhere, link to app.ardrive.io.
  final linkOrigin = kIsWeb ? Uri.base.origin : 'https://app.ardrive.io';
  final driveName = drive.name;

  var driveShareLink = '$linkOrigin/#/drives/${drive.id}?name=' +
      Uri.encodeQueryComponent(driveName);
  if (drive.isPrivate && driveKey != null) {
    final driveKeyBase64 = encodeBytesToBase64(await driveKey.extractBytes());

    driveShareLink = driveShareLink + '&driveKey=$driveKeyBase64';
  }
  return Uri.parse(driveShareLink);
}

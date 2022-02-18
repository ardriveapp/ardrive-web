import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/entities/string_types.dart';
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
  final linkOrigin = kIsWeb ? Uri.base.origin : linkOriginProduction;
  final driveName = drive.name;

  var driveShareLink = '$linkOrigin/#/drives/${drive.id}?name=' +
      Uri.encodeQueryComponent(driveName);
  if (drive.isPrivate && driveKey != null) {
    final driveKeyBase64 = encodeBytesToBase64(await driveKey.extractBytes());

    driveShareLink = driveShareLink + '&driveKey=$driveKeyBase64';
  }
  return Uri.parse(driveShareLink);
}

Future<Uri> generateFileShareLink({
  required FileEntry file,
  required Privacy drivePrivacy,
  SecretKey? fileKey,
}) async {
  // On web, link to the current origin the user is on.
  // Elsewhere, link to app.ardrive.io.
  final linkOrigin = kIsWeb ? Uri.base.origin : linkOriginProduction;
  var fileShareLink = '$linkOrigin/#/file/${file.id}/view';

  if (drivePrivacy == DrivePrivacy.private && fileKey != null) {
    final fileKeyBase64 = encodeBytesToBase64(await fileKey.extractBytes());

    fileShareLink = fileShareLink + '?fileKey=$fileKeyBase64';
  }
  return Uri.parse(fileShareLink);
}

import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

Uri generatePublicDriveShareLink({
  required final DriveID driveId,
  required final String driveName,
}) {
  // On web, link to the current origin the user is on.
  // Elsewhere, link to app.ardrive.io.
  final linkOrigin = kIsWeb ? Uri.base.origin : linkOriginProduction;

  final driveShareLink = '$linkOrigin/#/drives/$driveId?name=${Uri.encodeQueryComponent(driveName)}';
  return Uri.parse(driveShareLink);
}

Future<Uri> generatePrivateDriveShareLink({
  required final DriveID driveId,
  required final String driveName,
  required final SecretKey driveKey,
}) async {
  final driveKeyBase64 = encodeBytesToBase64(await driveKey.extractBytes());

  return Uri.parse(
    '${generatePublicDriveShareLink(driveName: driveName, driveId: driveId)}&driveKey=$driveKeyBase64',
  );
}

Uri generatePublicFileShareLink({
  required FileID fileId,
}) {
  // On web, link to the current origin the user is on.
  // Elsewhere, link to app.ardrive.io.
  final linkOrigin = kIsWeb ? Uri.base.origin : linkOriginProduction;
  final fileShareLink = '$linkOrigin/#/file/$fileId/view';

  return Uri.parse(fileShareLink);
}

Future<Uri> generatePrivateFileShareLink({
  required FileID fileId,
  required SecretKey fileKey,
}) async {
  final fileKeyBase64 = encodeBytesToBase64(await fileKey.extractBytes());

  return Uri.parse(
    '${generatePublicFileShareLink(fileId: fileId)}?fileKey=$fileKeyBase64',
  );
}

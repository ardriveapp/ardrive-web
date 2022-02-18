import 'package:ardrive/models/models.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

Future<Uri> generateDriveShareLink(
    {required Drive drive, SecretKey? driveKey}) async {
  // On web, link to the current origin the user is on.
  // Elsewhere, link to app.ardrive.io.
  final hostName = kIsWeb ? Uri.base.host : 'app.ardrive.io';
  final driveName = drive.name;

  final params = {'name': driveName};
  if (drive.isPrivate && driveKey != null) {
    final driveKeyBase64 = encodeBytesToBase64(await driveKey.extractBytes());
    params['driveKey'] = driveKeyBase64;
  }

  final uri = Uri.https(hostName, '/drives/${drive.id}', params);
  print(uri.pathSegments);
  return uri;
}

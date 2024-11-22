import 'dart:convert';

import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_io/ardrive_io.dart';

/// Checks if a file is an Arweave manifest file by examining its content type and contents.
///
/// Returns true if the file has JSON content type and contains the string "arweave/paths",
/// which indicates it follows the Arweave path manifest specification.
Future<bool> isCustomManifest(IOFile file) async {
  try {
    if (file.contentType == 'application/json') {
      final fileLength = await file.length;

      int bytesToRead = 100;

      if (fileLength < bytesToRead) {
        bytesToRead = fileLength;
      }

      /// Read the first 100 bytes of the file
      final first100Bytes = file.openReadStream(0, bytesToRead);

      String content = '';

      await for (var bytes in first100Bytes) {
        content += utf8.decode(bytes);
      }

      /// verify if file contains "arweave/paths"
      if (content.contains('arweave/paths')) {
        return true;
      }
    }
    return false;
  } catch (e) {
    logger.e('Error checking if file is a custom manifest', e);
    return false;
  }
}

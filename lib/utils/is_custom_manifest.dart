import 'dart:convert';

import 'package:ardrive_io/ardrive_io.dart';

/// Checks if a file is an Arweave manifest file by examining its content type and contents.
///
/// Returns true if the file has JSON content type and contains the string "arweave/paths",
/// which indicates it follows the Arweave path manifest specification.
Future<bool> isCustomManifest(IOFile file) async {
  if (file.contentType == 'application/json') {
    /// Read the first 100 bytes of the file
    final first100Bytes = file.openReadStream(0, 100);

    await for (var bytes in first100Bytes) {
      // verify if file contains "arweave/paths"f
      if (utf8.decode(bytes).contains('arweave/paths')) {
        return true;
      }
    }
  }
  return false;
}

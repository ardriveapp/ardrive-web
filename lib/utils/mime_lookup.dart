import 'package:mime/mime.dart' as mime;

/// Matches all strings that ends with `.gz` or `.tgz` and has at least one character before that
final gZipRegExp = RegExp('.\\.(gz|tgz)\$');

const applicationGZip = 'application/gzip';

String? lookupMimeType(String path, {List<int>? headerBytes}) {
  final pathMatch = gZipRegExp.firstMatch(path);
  if (pathMatch != null) {
    return applicationGZip;
  }
  return mime.lookupMimeType(path, headerBytes: headerBytes);
}

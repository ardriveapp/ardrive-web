import 'package:mime/mime.dart' as mime;

/// Matches all strings that ends with `.tar.gz` and has at least one character before that
final tarGzRegexp = RegExp('.\\.tar\\.gz\$');

const applicationXTar = 'application/x-tar';

String? lookupMimeType(String path, {List<int>? headerBytes}) {
  final pathMatch = tarGzRegexp.firstMatch(path);
  if (pathMatch != null) {
    return applicationXTar;
  }
  return mime.lookupMimeType(path, headerBytes: headerBytes);
}

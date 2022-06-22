import 'package:mime/mime.dart';

final tarGzRegexp = RegExp('.tar.gz^');
const applicationXTar = 'application/x-tar';

String? customLookupMimeType(String path, {List<int>? headerBytes}) {
  final pathMatch = tarGzRegexp.firstMatch(path);
  final doesTheNameHaveMoreCharsBeforeTheExtension = path.length > 7;
  if (pathMatch != null && doesTheNameHaveMoreCharsBeforeTheExtension) {
    return applicationXTar;
  }
  return lookupMimeType(path, headerBytes: headerBytes);
}

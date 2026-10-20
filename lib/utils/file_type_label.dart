import 'package:ardrive/entities/constants.dart';
import 'package:path/path.dart' as path;

final _shortWord = RegExp(r'^[a-z0-9]{1,5}$', caseSensitive: false);

/// What kind of file this is, in a word, for under its name in a preview.
///
/// The preview shows the name without its extension, so this is first the
/// extension: TXT, JPG, PDF. Without one, the end of the content type, which
/// is usually the same: PNG, JSON. That used to be the whole rule, and a
/// manifest read X.ARWEAVE-MANIFEST+JSON, as did any type a vendor named.
/// So a manifest says so in words, given as [manifestLabel], and a type with
/// no short word in it is shown as it is.
String fileTypeLabel({
  required String contentType,
  required String fileName,
  required String manifestLabel,
}) {
  // Without parameters: `text/plain; charset=utf-8` is `text/plain`.
  final mediaType = contentType.split(';').first.trim();

  if (mediaType == ContentType.manifest) {
    return manifestLabel;
  }

  final extension = path.extension(fileName).replaceFirst('.', '');
  if (_shortWord.hasMatch(extension)) {
    return extension.toUpperCase();
  }

  final subtype = mediaType.substring(mediaType.lastIndexOf('/') + 1);
  if (_shortWord.hasMatch(subtype)) {
    return subtype.toUpperCase();
  }

  return contentType;
}

/// What a release build prints for an exception that has no `toString` of its
/// own: `Instance of 'minified:Xy'`, or `minified:Xy` for an `Equatable` one
/// (whose `stringify` is off outside debug). Debug builds print the real
/// class name inside the same `Instance of '...'`.
final _opaquePart = RegExp(r"Instance of '[^']*'|minified:[A-Za-z0-9_$]+");

/// Whether [text], an error's `toString()`, tells a person nothing at all.
///
/// Only the whole message counts: one with something readable around the
/// opaque part, such as a drive's name, is not opaque. A leading
/// `Exception: ` is ignored, since that is all `Exception('$e')` adds.
bool isOpaqueErrorText(String text) {
  var rest = text.trim();
  if (rest.startsWith('Exception:')) {
    rest = rest.substring('Exception:'.length).trim();
  }
  return rest.replaceAll(_opaquePart, '').trim().isEmpty;
}

/// [text] with each opaque part replaced by [replacement], so the readable
/// rest of it, such as a drive's name, survives.
String withoutOpaqueParts(String text,
        {String replacement = 'Unknown error'}) =>
    text.replaceAll(_opaquePart, replacement);

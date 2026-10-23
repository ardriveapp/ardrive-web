/// Reads the `content` of the page's `<meta name="ardrive-library">` tag, the
/// switch that puts the app in library mode, and the page's title. See
/// `LibraryMode`.
///
/// Off the web there is no page, so it returns null.
library;

export 'library_meta_reader_stub.dart'
    if (dart.library.html) 'library_meta_reader_web.dart';

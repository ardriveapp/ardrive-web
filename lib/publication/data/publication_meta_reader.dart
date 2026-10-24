/// Reads the `content` of the page's `<meta name="ardrive-publication">` tag, the
/// switch that puts the app in publication mode, and the page's title. See
/// `PublicationMode`.
///
/// Off the web there is no page, so it returns null.
library;

export 'publication_meta_reader_stub.dart'
    if (dart.library.html) 'publication_meta_reader_web.dart';

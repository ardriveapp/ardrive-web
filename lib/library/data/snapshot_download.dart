/// Downloads a library's snapshot in the browser, reporting progress as the
/// body arrives. The web `http` client hands over a body only once it is
/// complete, so the loading screen could not say how far along it is.
///
/// Off the web there is none, and `LibrarySource` reads through its client.
library;

export 'snapshot_download_stub.dart'
    if (dart.library.html) 'snapshot_download_web.dart';

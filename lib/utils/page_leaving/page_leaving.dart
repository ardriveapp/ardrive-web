/// Whether the page is being closed or reloaded: set by the browser's
/// `beforeunload` and `pagehide`, cleared if the page is shown again.
///
/// Watching starts with [watchPageLeaving], so call it before the moment
/// that matters. Off the web the page never leaves.
library;

export 'page_leaving_stub.dart' if (dart.library.html) 'page_leaving_web.dart';

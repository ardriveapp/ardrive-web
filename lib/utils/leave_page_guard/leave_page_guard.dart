/// Asks the browser to confirm before the page is closed or reloaded, while
/// anything holds the guard.
///
/// For work that is lost, or paid for and lost, if the tab goes away midway:
/// an upload paid from the wallet posts its transaction before its data, so
/// closing the tab between the two leaves a paid transaction with nothing in
/// it. The browser shows its own wording; a page cannot set the text.
///
/// Holders are counted, so overlapping work can each hold and release without
/// releasing the other's. Off the web it does nothing.
library;

export 'leave_page_guard_stub.dart'
    if (dart.library.html) 'leave_page_guard_web.dart';

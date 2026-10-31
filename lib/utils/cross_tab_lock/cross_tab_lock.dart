import 'cross_tab_lock_stub.dart'
    if (dart.library.html) 'cross_tab_lock_web.dart' as impl;

/// Runs [body] while holding the Web Lock [name], so no other tab of the app
/// runs a body under the same name at the same time.
///
/// For a decision several tabs could make at once from shared storage, such
/// as which one makes a new account's first drive. Off the web, and in a
/// browser without Web Locks, there is nothing to coordinate with and [body]
/// just runs.
Future<T> runExclusiveAcrossTabs<T>(String name, Future<T> Function() body) =>
    impl.runExclusiveAcrossTabs(name, body);

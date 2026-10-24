/// Points the download helper at the publication's own gateway.
///
/// Browsers without the File System Access API (Firefox, Safari) save a
/// download through StreamSaver.js, which opens a helper page with a service
/// worker. The app's copy names that page on arweave.net, a host a publication
/// page must not reach; the same transaction is served by every gateway.
///
/// Off the web there is no helper, and this does nothing.
library;

export 'download_helper_stub.dart'
    if (dart.library.html) 'download_helper_web.dart';

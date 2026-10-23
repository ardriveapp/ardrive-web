/// Whether a library page may fetch [uri] (docs/LIBRARY_PAGES.md, "How a page
/// opens"): only from the host serving the page and the gateway it detected,
/// including the gateway's per-transaction subdomains, which is where it
/// sends data. Anything an owner wrote, such as an image in a note, is
/// checked here before the browser is asked for it.
bool libraryMayFetch(
  Uri uri, {
  required Uri page,
  required Uri gateway,
}) {
  if (!uri.hasScheme) return true;
  if (uri.scheme != 'https' && uri.scheme != 'http') return false;
  final host = uri.host.toLowerCase();
  final gatewayHost = gateway.host.toLowerCase();
  return host == page.host.toLowerCase() ||
      host == gatewayHost ||
      host.endsWith('.$gatewayHost');
}

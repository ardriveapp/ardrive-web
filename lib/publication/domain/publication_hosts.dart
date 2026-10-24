/// Whether a publication may fetch [uri] (docs/PUBLICATIONS.md, "How a page
/// opens"): only from the host serving the page and the gateway it detected,
/// including the gateway's per-transaction subdomains, which is where it
/// sends data. Anything an owner wrote, such as an image in a note, is
/// checked here before the browser is asked for it.
bool publicationMayFetch(
  Uri uri, {
  required Uri page,
  required Uri gateway,
}) {
  // A relative path resolves against the page. `//host/x` has no scheme
  // either, but names a host of its own, so it is checked like any other.
  if (!uri.hasScheme && !uri.hasAuthority) return true;
  if (uri.hasScheme && uri.scheme != 'https' && uri.scheme != 'http') {
    return false;
  }
  final host = uri.host.toLowerCase();
  final gatewayHost = gateway.host.toLowerCase();
  return host == page.host.toLowerCase() ||
      host == gatewayHost ||
      host.endsWith('.$gatewayHost');
}

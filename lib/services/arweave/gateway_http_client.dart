/// The HTTP client that reads data from a gateway.
///
/// In the browser this has to be a fetch-based client. `package:http`'s own
/// `BrowserClient` is built on `XMLHttpRequest` in the version this app can
/// use (1.2; the fetch-based ones need Dart 3.4), and it hands over a response
/// only once its *last* byte has arrived, as a single chunk. That makes a body
/// impossible to watch arrive, and it turns any timeout on `send` into a
/// deadline for the whole body rather than for the first byte.
library;

export 'gateway_http_client_io.dart'
    if (dart.library.html) 'gateway_http_client_web.dart';

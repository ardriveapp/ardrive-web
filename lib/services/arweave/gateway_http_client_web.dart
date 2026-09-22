import 'package:fetch_client/fetch_client.dart';
import 'package:http/http.dart';

/// See `gateway_http_client.dart`.
///
/// `RequestMode.cors` is not optional: the client's default is `noCors`, whose
/// responses are opaque, so every body would read as empty.
Client gatewayHttpClient() => FetchClient(mode: RequestMode.cors);

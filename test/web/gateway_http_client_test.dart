@TestOn('browser')
library;

import 'dart:convert';

import 'package:ardrive/services/arweave/gateway_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';

/// The gateway client the browser build uses, in a real browser engine.
///
/// Run with `flutter test --platform chrome test/web`. The VM run that CI does
/// skips it: [gatewayHttpClient] is the plain `package:http` client there, and
/// what matters is the fetch-based one.
///
/// A `data:` URL stands in for a gateway. The browser answers it itself, with
/// a real `Content-Type`, so the test needs no network and cannot flake.
void main() {
  const body = 'hello, gateway';
  final url = Uri.parse(
    'data:text/plain;charset=utf-8,${Uri.encodeComponent(body)}',
  );

  test('the response keeps its headers', () async {
    // The raw transaction viewer reads the served `Content-Type` to decide how
    // strictly to present a transaction. ArDrive's fetch_client fork used to
    // drop every header on the floor.
    final client = gatewayHttpClient();

    final response = await Response.fromStream(
      await client.send(Request('GET', url)),
    );

    expect(response.headers['content-type'], startsWith('text/plain'));

    client.close();
  });

  test('the body arrives intact', () async {
    final client = gatewayHttpClient();

    final response = await Response.fromStream(
      await client.send(Request('GET', url)),
    );

    expect(utf8.decode(response.bodyBytes), body);

    client.close();
  });
}

import 'dart:async';

import 'package:ardrive/utils/logger.dart';
import 'package:http/http.dart' as http;

/// Checks a name a file's metadata claims before a visitor sees it
/// (docs/NAMES.md, "Visitors"): the hint is only shown once the gateway
/// resolves the name to that file's data.
///
/// ar.io gateways answer a request to `<name>.<gateway host>` with the
/// transaction the name resolved to in `X-ArNS-Resolved-Id`, exposed to
/// browsers by their CORS policy (`exposedHeaders: '*'` in ar-io-node).
///
/// One request per name, cached for the session; a failure is "not
/// confirmed", never an error.
class ArNSNameVerifier {
  ArNSNameVerifier({
    required String Function() gatewayUrl,
    http.Client? client,
  })  : _gatewayUrl = gatewayUrl,
        _client = client ?? http.Client();

  final String Function() _gatewayUrl;
  final http.Client _client;
  final _resolved = <String, Future<String?>>{};

  /// The session's verifier, shared by every row.
  static ArNSNameVerifier? session;

  /// Whether [literalName] (`blog_acme`) points at [dataTxId] now.
  Future<bool> confirms(String literalName, String dataTxId) async =>
      await resolve(literalName) == dataTxId;

  /// What [literalName] resolves to, or null.
  Future<String?> resolve(String literalName) =>
      _resolved[literalName.toLowerCase()] ??= _head(literalName);

  Future<String?> _head(String literalName) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,63}$').hasMatch(literalName)) return null;
    try {
      final gateway = Uri.parse(_gatewayUrl());
      final uri = gateway.replace(
        host: '${literalName.toLowerCase()}.${gateway.host}',
        path: '/',
        query: null,
      );
      final response =
          await _client.head(uri).timeout(const Duration(seconds: 10));
      return response.headers['x-arns-resolved-id'];
    } catch (e) {
      logger.d('Could not resolve the name $literalName: $e');
      return null;
    }
  }
}

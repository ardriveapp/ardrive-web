import 'dart:async';
import 'dart:collection';

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
/// One request per name, kept for [_keptFor], a record's standard cache
/// time, so a name pointed elsewhere stops showing. A failure is "not
/// confirmed", never an error, and is asked again after [_failureKeptFor]:
/// a gateway that was busy once doesn't hide the name for the session. At
/// most [_concurrency] requests run at once, each to its own subdomain.
class ArNSNameVerifier {
  ArNSNameVerifier({
    required String Function() gatewayUrl,
    http.Client? client,
    DateTime Function()? clock,
  })  : _gatewayUrl = gatewayUrl,
        _client = client ?? http.Client(),
        _clock = clock ?? DateTime.now;

  final String Function() _gatewayUrl;
  final http.Client _client;
  final DateTime Function() _clock;
  final _resolved = <String, _Answer>{};

  static const _keptFor = Duration(minutes: 5);
  static const _failureKeptFor = Duration(minutes: 1);
  static const _concurrency = 4;
  int _inFlight = 0;
  final _waiting = Queue<Completer<void>>();

  /// The session's verifier, shared by every row.
  static ArNSNameVerifier? session;

  /// Whether [literalName] (`blog_acme`) points at [dataTxId] now.
  Future<bool> confirms(String literalName, String dataTxId) async =>
      await resolve(literalName) == dataTxId;

  /// What [literalName] resolves to, or null.
  Future<String?> resolve(String literalName) {
    final key = literalName.toLowerCase();
    final cached = _resolved[key];
    if (cached != null && cached.isFresh(_clock())) return cached.value;
    final answer = _Answer();
    _resolved[key] = answer;
    return answer.value = _limited(() => _head(literalName)).then((read) {
      answer.expires = _clock().add(read.failed ? _failureKeptFor : _keptFor);
      return read.resolvedId;
    });
  }

  Future<T> _limited<T>(Future<T> Function() run) async {
    while (_inFlight >= _concurrency) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    _inFlight++;
    try {
      return await run();
    } finally {
      _inFlight--;
      if (_waiting.isNotEmpty) _waiting.removeFirst().complete();
    }
  }

  Future<({String? resolvedId, bool failed})> _head(String literalName) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,63}$').hasMatch(literalName)) {
      return (resolvedId: null, failed: false);
    }
    try {
      final gateway = Uri.parse(_gatewayUrl());
      final uri = gateway.replace(
        host: '${literalName.toLowerCase()}.${gateway.host}',
        path: '/',
        query: null,
      );
      final response =
          await _client.head(uri).timeout(const Duration(seconds: 10));
      return (
        resolvedId: response.headers['x-arns-resolved-id'],
        failed: response.statusCode == 429 || response.statusCode >= 500,
      );
    } catch (e) {
      logger.d('Could not resolve the name $literalName: $e');
      return (resolvedId: null, failed: true);
    }
  }
}

/// One name's answer, and until when it holds; none while it is read.
class _Answer {
  late Future<String?> value;
  DateTime? expires;

  bool isFresh(DateTime now) {
    final until = expires;
    return until == null || now.isBefore(until);
  }
}

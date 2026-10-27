import 'dart:convert';

import 'package:http/http.dart' as http;

/// Who signed a transaction, as one GraphQL lookup on the gateway serving a
/// publication says: the one request a publication makes beyond its own
/// files and their data (docs/PUBLICATIONS.md, "How a page opens").
///
/// `publication.json` names its owner, and anyone can write one naming
/// anyone. The snapshot's own signer cannot be claimed that way.
class PublicationOwnerLookup {
  PublicationOwnerLookup({required Uri gateway, http.Client? client})
      : _gateway = gateway,
        _client = client ?? http.Client();

  final Uri _gateway;
  final http.Client _client;

  /// The address that signed [txId], or null when the gateway has not
  /// indexed it (yet). Throws when the gateway cannot be asked.
  Future<String?> ownerOf(String txId) async {
    final response = await _client
        .post(
          _gateway.resolve('/graphql'),
          headers: const {'content-type': 'application/json'},
          body: json.encode({
            'query': r'query($id: ID!) { transactions(ids: [$id]) '
                '{ edges { node { id owner { address } } } } }',
            'variables': {'id': txId},
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw PublicationOwnerLookupException(
          'GraphQL answered ${response.statusCode}');
    }
    final Object? body;
    try {
      body = json.decode(utf8.decode(response.bodyBytes));
    } on FormatException catch (e) {
      throw PublicationOwnerLookupException('not JSON: ${e.message}');
    }
    final edges = switch (body) {
      {'data': {'transactions': {'edges': final List edges}}} => edges,
      _ => throw const PublicationOwnerLookupException('no transactions'),
    };
    for (final edge in edges) {
      if (edge
          case {
            'node': {
              'id': final String id,
              'owner': {'address': final String address}
            }
          } when id == txId) {
        return address;
      }
    }
    return null;
  }
}

class PublicationOwnerLookupException implements Exception {
  const PublicationOwnerLookupException(this.message);

  final String message;

  @override
  String toString() => 'PublicationOwnerLookupException: $message';
}

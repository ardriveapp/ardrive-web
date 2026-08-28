import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:flutter_test/flutter_test.dart';

/// The cipher path must not be breakable by a field it does not read.
///
/// A gateway answered a real `TransactionDetails` request with:
///
///     "signature": "<not-found>",
///     "anchor": null,
///     "recipient": "",
///
/// The schema declares `anchor` as `String!`, so Artemis fails deserialization
/// for the **whole** query - and `TransactionDetails` was where the preview and
/// the download read `Cipher` and `Cipher-IV`. One unindexed field a gateway
/// had no obligation to have therefore broke every private preview and every
/// private download on that gateway, with a `JSNull is not a subtype of String`
/// nowhere near the cause.
///
/// The four fields now live on `TransactionDetailsWithSignature`, so a caller
/// asking for verification can be told it is unavailable while the cipher path
/// carries on.
void main() {
  const txId = 'kngNLKJ9pwgEPjudYEmoimWbJpMC157JMlIWUvEzA7E';

  /// The gateway's real answer, with the fields it did not index.
  Map<String, dynamic> queryJson({Object? anchor}) => {
        'transaction': {
          'id': txId,
          'owner': {'address': 'iKryOeZQMONi2965nKz528htMMN_sBcjlhc-VncoRjA'},
          'bundledIn': {'id': 'hNJY7zI8si6qyBNfTbHIN6XVOUydn5DJMOekqqo-Jbw'},
          'block': {'height': 884207, 'timestamp': 1646230817},
          'tags': [
            {'name': 'Cipher', 'value': 'AES256-GCM'},
            {'name': 'Cipher-IV', 'value': '-wVYY6lk0T1-cUYY'},
          ],
          'signature': '<not-found>',
          'anchor': anchor,
          'recipient': '',
          'ownerKey': {'key': 'qD2kJ8bGgP3WiGEDkPk96nz7'},
        },
      };

  test('the cipher query survives a gateway that indexes nothing extra', () {
    // The same response that broke the old query. Nothing it carries is
    // selected any more except the tags, so there is nothing left to fail on.
    final tx = TransactionDetails$Query.fromJson(queryJson()).transaction!;

    expect(tx.id, txId);
    expect(
      tx.tags.firstWhere((t) => t.name == 'Cipher').value,
      'AES256-GCM',
    );
    expect(
      tx.tags.firstWhere((t) => t.name == 'Cipher-IV').value,
      '-wVYY6lk0T1-cUYY',
    );
    expect(tx.bundledIn?.id, 'hNJY7zI8si6qyBNfTbHIN6XVOUydn5DJMOekqqo-Jbw');
  });

  test('the verifier query is the one that carries the risk', () {
    // Recorded rather than fixed: this query really does fail on a null
    // `anchor`, because the schema promises it cannot be null. That is
    // survivable now only because the caller is asking for verification, which
    // may be reported unavailable - and because nothing in the app asks.
    expect(
      () => TransactionDetailsWithSignature$Query.fromJson(queryJson()),
      throwsA(isA<TypeError>()),
    );

    // With the field indexed it reads as it always did.
    final tx = TransactionDetailsWithSignature$Query.fromJson(
      queryJson(anchor: ''),
    ).transaction!;

    expect(tx.anchor, '');
    expect(tx.signature, '<not-found>');
  });
}

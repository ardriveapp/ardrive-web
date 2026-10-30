import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the shape the integrity verifier reads off the
/// `TransactionDetailsWithSignature` query.
///
/// Split out of `TransactionDetails` because the schema declares `signature`,
/// `anchor` and `recipient` non-null while gateways that do not index them
/// answer `null` - which fails deserialization for the whole query, and took
/// the `Cipher` tags of every private preview and download with it.
///
/// The generated class comes from `build_runner` reading
/// `lib/services/arweave/graphql/queries/SingleTransactionWithSignature.graphql`,
/// so an edit to that document shows up here before it reaches the download
/// layer.
void main() {
  group('TransactionDetailsWithSignature query', () {
    const txId = 'Y_KKT8o1vCZWxFjgUnlPRUssaoCnZ2Pi-5aYabBFQRw';
    const bundleId = 'tUP8KDUehmGvkUh5-GfIQVSBxilxL2jhM1wlMbhr_QQ';
    const ownerAddress = 'jj-AdCJbhyAkzMJwkPR4WTAHqQ_I-aVuTbm8Gc1jX_o';
    const dataItemSignature = 'EwvcZLp1jhn73FhQji1P6XbkJyahJ1JnfkIBHgvVTC5';
    const dataItemOwnerKey = 'BNHYYAzq9YNP5wMfUAcZzIg9ScDQJ1ZOyNqK2qMT4S9';

    Map<String, dynamic> queryJson({
      String? bundledIn = bundleId,
      String signature = dataItemSignature,
      String anchor = '',
      String recipient = '',
      String ownerKey = dataItemOwnerKey,
    }) =>
        {
          'transaction': {
            'id': txId,
            'owner': {'address': ownerAddress},
            'bundledIn': bundledIn == null ? null : {'id': bundledIn},
            'block': {'height': 1956073, 'timestamp': 1783686709},
            'tags': [
              {'name': 'Cipher', 'value': 'AES256-GCM'},
              {'name': 'Cipher-IV', 'value': 'qq7hVeSMhWk1sPGD'},
            ],
            'signature': signature,
            'anchor': anchor,
            'recipient': recipient,
            'ownerKey': {'key': ownerKey},
          },
        };

    test('carries the deep hash inputs of a bundled data item', () {
      final tx = TransactionDetailsWithSignature$Query.fromJson(queryJson()).transaction!;

      expect(tx.bundledIn?.id, bundleId);
      expect(tx.signature, dataItemSignature);
      expect(tx.ownerKey.key, dataItemOwnerKey);
      expect(tx.anchor, isEmpty);
      expect(tx.recipient, isEmpty);
    });

    test('keeps everything TransactionCommon already provided', () {
      final tx = TransactionDetailsWithSignature$Query.fromJson(queryJson()).transaction!;

      expect(tx.id, txId);
      expect(tx.owner.address, ownerAddress);
      expect(tx.block?.height, 1956073);
      expect(
        tx.tags.map((tag) => tag.name),
        containsAll(<String>['Cipher', 'Cipher-IV']),
      );
    });

    test('an L1 transaction is the one without a bundle', () {
      final tx = TransactionDetailsWithSignature$Query.fromJson(
        queryJson(bundledIn: null),
      ).transaction!;

      expect(tx.bundledIn, isNull);
      expect(tx.signature, isNotEmpty);
    });

    test('fields a gateway does not index arrive empty, never null', () {
      final tx = TransactionDetailsWithSignature$Query.fromJson(
        queryJson(signature: '', ownerKey: ''),
      ).transaction!;

      expect(tx.signature, isEmpty);
      expect(tx.ownerKey.key, isEmpty);
    });
  });
}

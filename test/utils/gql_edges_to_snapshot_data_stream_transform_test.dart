import 'dart:convert';

import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/utils/snapshots/gql_edges_to_snapshot_data_stream_transform.dart';
import 'package:ardrive/utils/snapshots/snapshot_types.dart';
import 'package:flutter_test/flutter_test.dart';

// stream of fake TxSnapshot items
Stream<TxSnapshot> fakeTxSnapshotStream(int amount) async* {
  for (var i = 0; i < amount; i++) {
    yield TxSnapshot(
      gqlNode:
          DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
              .fromJson(
        {
          'id': 'id_$i',
          'name': 'name_$i',
          'owner': {
            'address': 'owner_$i',
          },
          'lastModifiedDate': '${i * 10}',
          'size': '${i * 10}',
          'dataTxId': 'dataTxId_$i',
          'entityTxId': 'entityTxId_$i',
          'bundledIn': {
            'id': 'bundleTxId_$i',
          },
          'tags': [],
        },
      ),
      jsonMetadata: '{"name": "name_$i"}',
    );
  }
}

// Test sheet for the gqlEdgesToSnapshotDataStreamTransform method
void main() {
  const emptyStreamOfTxSnapshot = Stream<TxSnapshot>.empty();
  final Stream<TxSnapshot> streamOfFakeTxSnapshots = fakeTxSnapshotStream(3);

  group('gqlEdgesToSnapshotDataStreamTransform transform method', () {
    test('should return an empty stream when given an empty stream', () async {
      final result = gqlEdgesToSnapshotDataStreamTransform(
        emptyStreamOfTxSnapshot,
      );

      expect(result, emitsInOrder([]));
    });

    test('should return the expected SnapshotData', () async {
      final result = gqlEdgesToSnapshotDataStreamTransform(
        streamOfFakeTxSnapshots,
      );

      // Await for the whole stream data and transform into string
      final streamResult =
          await result.map((event) => utf8.decode(event)).join('');

      expect(streamResult,
          '{"txSnapshots":[{"gqlNode":{"id":"id_0","owner":{"address":"owner_0"},"bundledIn":{"id":"bundleTxId_0"},"block":null,"tags":[]},"jsonMetadata":"{\\"name\\": \\"name_0\\"}"},{"gqlNode":{"id":"id_1","owner":{"address":"owner_1"},"bundledIn":{"id":"bundleTxId_1"},"block":null,"tags":[]},"jsonMetadata":"{\\"name\\": \\"name_1\\"}"},{"gqlNode":{"id":"id_2","owner":{"address":"owner_2"},"bundledIn":{"id":"bundleTxId_2"},"block":null,"tags":[]},"jsonMetadata":"{\\"name\\": \\"name_2\\"}"}]}');
    });
  });
}

import 'dart:convert';

import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/sync/domain/models/drive_entity_history.dart';
import 'package:ardrive/utils/snapshots/range.dart';

Future<String> fakePrivateSnapshotSource(Range range) async {
  return jsonEncode(
    {
      'txSnapshots': await fakeNodesStream(range)
          .map(
            (event) => {
              'gqlNode': event.transactionCommonMixin,
              'jsonMetadata': base64Encode(
                utf8.encode(
                    ('ENCODED DATA - H:${event.transactionCommonMixin.block!.height}')),
              ),
            },
          )
          .toList(),
    },
  );
}

Future<String> fakeSnapshotSource(Range range) async {
  return jsonEncode(
    {
      'txSnapshots': await fakeNodesStream(range)
          .map(
            (event) => {
              'gqlNode': event.transactionCommonMixin,
              'jsonMetadata':
                  '{"name": "${event.transactionCommonMixin.block!.height}"}',
            },
          )
          .toList(),
    },
  );
}

// TODO: use the abstraction DriveEntityHistoryTransactionModel
Stream<DriveEntityHistoryTransactionModel> fakeNodesStream(Range range) async* {
  for (int height = range.start; height <= range.end; height++) {
    final transactionCommonMixin =
        DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
            .fromJson(
      {
        'id': 'tx-$height',
        'bundledIn': {'id': 'ASDASDASDASDASDASD'},
        'owner': {'address': '1234567890'},
        'tags': [],
        'block': {
          'height': height,
          'timestamp': height * 100,
        }
      },
    );

    yield DriveEntityHistoryTransactionModel(
      transactionCommonMixin: transactionCommonMixin,
    );
  }
}

Future<int> countStreamItems(
    Stream<DriveEntityHistoryTransactionModel> stream) async {
  int count = 0;
  await for (var _ in stream) {
    count++;
  }
  return count;
}

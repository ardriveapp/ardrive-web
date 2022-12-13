import 'dart:convert';

import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/utils/snapshots/range.dart';

Future<String> fakeSnapshotSource(Range range) async {
  return jsonEncode(
    {
      'txSnapshots': await fakeNodesStream(range)
          .map(
            (event) => {
              'gqlNode': event,
              'jsonMetadata': '{"name": "${event.block!.height}"}',
            },
          )
          .toList(),
    },
  );
}

Stream<DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction>
    fakeNodesStream(Range range) async* {
  for (int height = range.start; height <= range.end; height++) {
    yield DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
        .fromJson(
      {
        'id': 'tx-$height',
        'bundledIn': {'id': 'ASDASDASDASDASDASD'},
        'owner': {'address': '1234567890'},
        'tags': [],
        'block': {
          'height': height,
          'timestamp': DateTime.now().microsecondsSinceEpoch
        }
      },
    );
  }
}

Future<int> countStreamItems(Stream stream) async {
  int count = 0;
  await for (DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction _
      in stream) {
    count++;
  }
  return count;
}

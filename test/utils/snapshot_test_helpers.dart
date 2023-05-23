import 'dart:convert';

import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/utils/snapshots/range.dart';

Future<String> fakePrivateSnapshotSource(Range range) async {
  return jsonEncode(
    {
      'txSnapshots': await fakeNodesStream(range)
          .map(
            (event) => {
              'gqlNode': event,
              'jsonMetadata': base64Encode(
                utf8.encode(('ENCODED DATA - H:${event.block!.height}')),
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
          'timestamp': height * 100,
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

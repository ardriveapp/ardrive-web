import 'dart:convert';

import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/segmented_gql_data.dart';
import 'package:ardrive/utils/snapshots/snapshot_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SnapshotItem class', () {
    group('fromStream factory', () {
      test('getStreamForIndex returns a valid stream of nodes', () async {
        final r = Range(start: 0, end: 10);

        SnapshotItem item = SnapshotItem.fromStream(
          blockStart: r.start,
          blockEnd: r.end,
          driveId: 'DRIVE_ID',
          subRanges: HeightRange(rangeSegments: [Range(start: 0, end: 10)]),
          source: fakeNodesStream(r),
        );
        expect(item.subRanges.rangeSegments.length, 1);
        expect(item.currentIndex, -1);
        Stream stream = item.getNextStream();
        expect(item.currentIndex, 0);
        expect(await countStreamItems(stream), 11);
        expect(
          () => item.getNextStream(),
          throwsA(isA<SubRangeIndexOverflow>()),
        );

        item = SnapshotItem.fromStream(
          blockStart: r.start,
          blockEnd: r.end,
          driveId: 'DRIVE_ID',
          subRanges: HeightRange(
            rangeSegments: [
              Range(start: 0, end: 4),
              Range(start: 6, end: 10),
            ],
          ),
          source: fakeNodesStream(r),
        );
        expect(item.subRanges.rangeSegments.length, 2);
        expect(item.currentIndex, -1);
        stream = item.getNextStream();
        expect(item.currentIndex, 0);
        expect(await countStreamItems(stream), 5);
        stream = item.getNextStream();
        expect(item.currentIndex, 1);
        expect(await countStreamItems(stream), 5);

        expect(
          () => item.getNextStream(),
          throwsA(isA<SubRangeIndexOverflow>()),
        );
      });
    });
    group('fromGQLNode factory', () {
      test('getStreamForIndex returns a valid stream of nodes', () async {
        final r = Range(start: 0, end: 10);

        SnapshotItem item = SnapshotItem.fromGQLNode(
          node:
              SnapshotEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
                  .fromJson(
            {
              'id': 'hwgMuTV_dtFqfC9fJXfZTv00aOm17yL0wYucqh05YAQ',
              'bundledIn': {'id': 'ASDASDASDASDASDASD'},
              'owner': {'address': '1234567890'},
              'tags': [
                {'name': 'Block-Start', 'value': '${r.start}'},
                {'name': 'Block-End', 'value': '${r.end}'},
                {'name': 'Drive-Id', 'value': 'asdasdasdasd'},
              ],
              'block': {
                'height': 100,
                'timestamp': DateTime.now().microsecondsSinceEpoch
              }
            },
          ),
          subRanges: HeightRange(rangeSegments: [r]),
          fakeSource: await fakeSnapshotStream(r),
        );
        expect(item.subRanges.rangeSegments.length, 1);
        expect(item.currentIndex, -1);
        Stream stream = item.getNextStream();
        expect(item.currentIndex, 0);
        expect(await countStreamItems(stream), 11);

        expect(
          () => item.getNextStream(),
          throwsA(isA<SubRangeIndexOverflow>()),
        );
      });
    });

    group('getDataForTxId method', () {
      test('returns cached data if present', () async {
        final r = Range(start: 0, end: 10);

        SnapshotItemOnChain item = SnapshotItem.fromGQLNode(
          node:
              SnapshotEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
                  .fromJson(
            {
              'id': 'hwgMuTV_dtFqfC9fJXfZTv00aOm17yL0wYucqh05YAQ',
              'bundledIn': {'id': 'ASDASDASDASDASDASD'},
              'owner': {'address': '1234567890'},
              'tags': [
                {'name': 'Block-Start', 'value': '${r.start}'},
                {'name': 'Block-End', 'value': '${r.end}'},
                {'name': 'Drive-Id', 'value': 'asdasdasdasd'},
              ],
              'block': {
                'height': 100,
                'timestamp': DateTime.now().microsecondsSinceEpoch
              }
            },
          ),
          subRanges: HeightRange(rangeSegments: [r]),
          fakeSource: await fakeSnapshotStream(r),
        ) as SnapshotItemOnChain;

        await countStreamItems(item.getNextStream());

        for (int height = r.start; height <= r.end; height++) {
          // has data the first time
          expect(SnapshotItemOnChain.getDataForTxId('$height'),
              '{"name": "$height"}');
          // further calls to the method results in a null response
          expect(SnapshotItemOnChain.getDataForTxId('$height'), null);
        }
      });

      test('returns null if no data present', () async {
        final r = Range(start: 0, end: 10);

        SnapshotItemOnChain item = SnapshotItem.fromGQLNode(
          node:
              SnapshotEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
                  .fromJson(
            {
              'id': 'hwgMuTV_dtFqfC9fJXfZTv00aOm17yL0wYucqh05YAQ',
              'bundledIn': {'id': 'ASDASDASDASDASDASD'},
              'owner': {'address': '1234567890'},
              'tags': [
                {'name': 'Block-Start', 'value': '${r.start}'},
                {'name': 'Block-End', 'value': '${r.end}'},
                {'name': 'Drive-Id', 'value': 'asdasdasdasd'},
              ],
              'block': {
                'height': 100,
                'timestamp': DateTime.now().microsecondsSinceEpoch
              }
            },
          ),
          subRanges: HeightRange(rangeSegments: [r]),
          fakeSource: await fakeSnapshotStream(r),
        ) as SnapshotItemOnChain;

        await countStreamItems(item.getNextStream());

        expect(SnapshotItemOnChain.getDataForTxId('not present tx id'), null);
      });
    });
  });
}

// TODO: move these helper methods to its own source file

Future<String> fakeSnapshotStream(Range range) async {
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
        'id': '$height',
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

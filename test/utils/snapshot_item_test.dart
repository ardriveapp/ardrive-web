import 'dart:convert';

import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/snapshot_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SnapshotItem class', () {
    // TODO: test the getter for the data when implemented

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
        Stream stream = item.getStreamForIndex(0);
        expect(await countStreamItems(stream), 11);
        expect(
          () async => await countStreamItems(stream),
          throwsA(isA<StateError>()),
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
        stream = item.getStreamForIndex(0);
        expect(await countStreamItems(stream), 5);
        stream = item.getStreamForIndex(1);
        expect(await countStreamItems(stream), 5);
        expect(
          () async => await countStreamItems(stream),
          throwsA(isA<StateError>()),
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
          fakeSource: (jsonEncode({
            'txSnapshots': await fakeNodesStream(r)
                .map(
                  (event) => {'gqlNode': event, 'jsonData': '{}'},
                )
                .toList()
          })),
        );
        expect(item.subRanges.rangeSegments.length, 1);
        Stream stream = item.getStreamForIndex(0);
        expect(await countStreamItems(stream), 11);
        expect(
          () async => await countStreamItems(stream),
          throwsA(isA<StateError>()),
        );
      });
    });
  });
}

Stream<DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction>
    fakeNodesStream(Range range) async* {
  for (int height = range.start; height <= range.end; height++) {
    yield DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
        .fromJson(
      {
        'id': 'hwgMuTV_dtFqfC9fJXfZTv00aOm17yL0wYucqh05YAQ',
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

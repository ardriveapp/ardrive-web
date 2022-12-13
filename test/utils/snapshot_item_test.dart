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
          fakeSource: await fakeSnapshotSource(r),
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

    group('instantiateSingle static method', () {
      test('instantiates a single item with the correct sub-ranges', () async {
        final totalSnapshotRange = Range(start: 0, end: 10);
        final obscuredBy = HeightRange(rangeSegments: []);

        final String snapshotItemSource = await fakeSnapshotSource(
          totalSnapshotRange,
        );

        final SnapshotEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
            snapshotTx =
            SnapshotEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
                .fromJson(
          {
            'id': 'tx-id',
            'bundledIn': {'id': 'ASDASDASDASDASDASD'},
            'owner': {'address': '1234567890'},
            'tags': [
              {'name': 'Block-Start', 'value': '0'},
              {'name': 'Block-End', 'value': '10'},
              {'name': 'Drive-Id', 'value': 'DRIVE_ID'},
            ],
            'block': {
              'height': 11,
              'timestamp': DateTime.now().microsecondsSinceEpoch
            }
          },
        );

        SnapshotItem item = SnapshotItem.instantiateSingle(
          snapshotTx,
          obscuredBy: obscuredBy,
          fakeSource: snapshotItemSource,
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

      test(
        'instantiates multiple items with the correct sub-ranges given the obscuredBy range',
        () async {
          final totalSnapshotRange = Range(start: 0, end: 10);
          final obscuredBy = HeightRange(rangeSegments: [totalSnapshotRange]);

          final String snapshotItemSource = await fakeSnapshotSource(
            totalSnapshotRange,
          );

          final SnapshotEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
              snapshotTx =
              SnapshotEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
                  .fromJson(
            {
              'id': 'tx-id',
              'bundledIn': {'id': 'ASDASDASDASDASDASD'},
              'owner': {'address': '1234567890'},
              'tags': [
                {'name': 'Block-Start', 'value': '0'},
                {'name': 'Block-End', 'value': '10'},
                {'name': 'Drive-Id', 'value': 'DRIVE_ID'},
              ],
              'block': {
                'height': 11,
                'timestamp': DateTime.now().microsecondsSinceEpoch
              }
            },
          );

          SnapshotItem item = SnapshotItem.instantiateSingle(
            snapshotTx,
            obscuredBy: obscuredBy,
            fakeSource: snapshotItemSource,
          );

          expect(item.subRanges.rangeSegments.length, 0);
          expect(item.currentIndex, -1);

          expect(
            () => item.getNextStream(),
            throwsA(isA<SubRangeIndexOverflow>()),
          );
        },
      );
    });

    group('instantiateAll static method', () {
      test(
        'instantiates multiple items with the correct sub-ranges',
        () async {
          final totalSnapshotRange = Range(start: 0, end: 10);

          final String snapshotItemSource = await fakeSnapshotSource(
            totalSnapshotRange,
          );

          final SnapshotEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
              snapshotTx =
              SnapshotEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
                  .fromJson(
            {
              'id': 'tx-id',
              'bundledIn': {'id': 'ASDASDASDASDASDASD'},
              'owner': {'address': '1234567890'},
              'tags': [
                {'name': 'Block-Start', 'value': '0'},
                {'name': 'Block-End', 'value': '10'},
                {'name': 'Drive-Id', 'value': 'DRIVE_ID'},
              ],
              'block': {
                'height': 11,
                'timestamp': DateTime.now().microsecondsSinceEpoch
              }
            },
          );

          List<SnapshotItem> allItems = await SnapshotItem.instantiateAll(
            Stream.fromIterable([snapshotTx, snapshotTx, snapshotTx]),
            fakeSource: snapshotItemSource,
          ).toList();

          expect(allItems[0].subRanges.rangeSegments.length, 1);
          expect(allItems[0].currentIndex, -1);
          Stream stream = allItems[0].getNextStream();
          expect(allItems[0].currentIndex, 0);
          expect(await countStreamItems(stream), 11);
          expect(
            () => allItems[0].getNextStream(),
            throwsA(isA<SubRangeIndexOverflow>()),
          );

          expect(allItems[1].subRanges.rangeSegments.length, 0);
          expect(allItems[1].currentIndex, -1);
          expect(
            () => allItems[1].getNextStream(),
            throwsA(isA<SubRangeIndexOverflow>()),
          );

          expect(allItems[2].subRanges.rangeSegments.length, 0);
          expect(allItems[2].currentIndex, -1);
          expect(
            () => allItems[2].getNextStream(),
            throwsA(isA<SubRangeIndexOverflow>()),
          );
        },
      );

      test(
        'instantiates multiple items with the correct sub-ranges given a lastBlockHeigh',
        () async {
          final totalSnapshotRange = Range(start: 0, end: 10);

          final String snapshotItemSource = await fakeSnapshotSource(
            totalSnapshotRange,
          );

          final SnapshotEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
              snapshotTx =
              SnapshotEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
                  .fromJson(
            {
              'id': 'tx-id',
              'bundledIn': {'id': 'ASDASDASDASDASDASD'},
              'owner': {'address': '1234567890'},
              'tags': [
                {'name': 'Block-Start', 'value': '0'},
                {'name': 'Block-End', 'value': '10'},
                {'name': 'Drive-Id', 'value': 'DRIVE_ID'},
              ],
              'block': {
                'height': 11,
                'timestamp': DateTime.now().microsecondsSinceEpoch
              }
            },
          );

          List<SnapshotItem> allItems = await SnapshotItem.instantiateAll(
            Stream.fromIterable([snapshotTx, snapshotTx]),
            lastBlockHeight: 100,
            fakeSource: snapshotItemSource,
          ).toList();

          expect(allItems[0].subRanges.rangeSegments.length, 0);
          expect(allItems[0].currentIndex, -1);
          expect(
            () => allItems[0].getNextStream(),
            throwsA(isA<SubRangeIndexOverflow>()),
          );

          expect(allItems[1].subRanges.rangeSegments.length, 0);
          expect(allItems[1].currentIndex, -1);
          expect(
            () => allItems[1].getNextStream(),
            throwsA(isA<SubRangeIndexOverflow>()),
          );
        },
      );
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
          fakeSource: await fakeSnapshotSource(r),
        ) as SnapshotItemOnChain;

        await countStreamItems(item.getNextStream());

        for (int height = r.start; height <= r.end; height++) {
          // has data the first time
          expect(
            await SnapshotItemOnChain.getDataForTxId('tx-$height'),
            utf8.encode(
              '{"name": "$height"}',
            ),
          );
          // further calls to the method results in a null response
          expect(await SnapshotItemOnChain.getDataForTxId('$height'), null);
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
          fakeSource: await fakeSnapshotSource(r),
        ) as SnapshotItemOnChain;

        await countStreamItems(item.getNextStream());

        expect(
          await SnapshotItemOnChain.getDataForTxId('not present tx id'),
          null,
        );
      });
    });
  });
}

// TODO: move these helper methods to its own source file

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

import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/segmented_gql_data.dart';
import 'package:ardrive/utils/snapshots/snapshot_drive_history.dart';
import 'package:ardrive/utils/snapshots/snapshot_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_utils/utils.dart';
import 'snapshot_test_helpers.dart';

void main() {
  final composableRanges = [
    // HeightRange(rangeSegments: []),
    HeightRange(rangeSegments: [Range(start: 0, end: 10)]),
    // HeightRange(rangeSegments: []),
    HeightRange(rangeSegments: [Range(start: 11, end: 100)]),
    HeightRange(rangeSegments: [Range(start: 101, end: 101)]),
    HeightRange(rangeSegments: [Range(start: 102, end: 200)]),
    // HeightRange(rangeSegments: []),
  ];
  final nonComposableRanges = [
    // #1
    // HeightRange(rangeSegments: []),
    HeightRange(rangeSegments: [Range(start: 0, end: 10)]),
    // HeightRange(rangeSegments: []),

    // #2
    HeightRange(rangeSegments: [Range(start: 50, end: 100)]),
    HeightRange(rangeSegments: [Range(start: 101, end: 101)]),
    HeightRange(rangeSegments: [Range(start: 102, end: 200)]),
    HeightRange(rangeSegments: [
      // #3
      Range(start: 210, end: 220),
      Range(start: 221, end: 221),

      // #4
      Range(start: 230, end: 250),
    ]),
    // HeightRange(rangeSegments: []),
  ];

  group('SnapshotDriveHistory class', () {
    late ArweaveService arweave = MockArweaveService();

    test('returns a single stream if the sub-ranges are composable', () async {
      final fakeItems = await Future.wait(composableRanges
          .map((h) => fakeSnapshotItemFromRange(
                h,
                arweave,
              ))
          .toList());
      final snapshotDriveHistory = SnapshotDriveHistory(items: fakeItems);

      expect(snapshotDriveHistory.subRanges.rangeSegments.length, 1);
      expect(snapshotDriveHistory.currentIndex, -1);
      expect(await countStreamItems(snapshotDriveHistory.getNextStream()), 201);
      expect(snapshotDriveHistory.currentIndex, 0);

      expect(
        () => snapshotDriveHistory.getNextStream(),
        throwsA(isA<SubRangeIndexOverflow>()),
      );
    });

    test('returns multiple streams if the sub-ranges are not composable',
        () async {
      final fakeItems = await Future.wait(nonComposableRanges
          .map((h) => fakeSnapshotItemFromRange(
                h,
                arweave,
              ))
          .toList());
      final snapshotDriveHistory = SnapshotDriveHistory(items: fakeItems);

      expect(snapshotDriveHistory.subRanges.rangeSegments.length, 4);
      expect(snapshotDriveHistory.currentIndex, -1);
      expect(await countStreamItems(snapshotDriveHistory.getNextStream()), 11);
      expect(snapshotDriveHistory.currentIndex, 0);
      expect(await countStreamItems(snapshotDriveHistory.getNextStream()), 151);
      expect(snapshotDriveHistory.currentIndex, 1);
      expect(await countStreamItems(snapshotDriveHistory.getNextStream()), 12);
      expect(snapshotDriveHistory.currentIndex, 2);
      expect(await countStreamItems(snapshotDriveHistory.getNextStream()), 21);
      expect(snapshotDriveHistory.currentIndex, 3);

      expect(
        () => snapshotDriveHistory.getNextStream(),
        throwsA(isA<SubRangeIndexOverflow>()),
      );
      //
    });
  });
}

Range heightRangeToRange(HeightRange hr) {
  return Range(
      start: hr.rangeSegments[0].start,
      end: hr.rangeSegments[hr.rangeSegments.length - 1].end);
}

Future<SnapshotItem> fakeSnapshotItemFromRange(
  HeightRange r,
  ArweaveService arweave,
) async {
  final range = heightRangeToRange(r);
  return SnapshotItem.fromGQLNode(
    arweave: arweave,
    node:
        SnapshotEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
            .fromJson(
      {
        'id': 'hwgMuTV_dtFqfC9fJXfZTv00aOm17yL0wYucqh05YAQ',
        'bundledIn': {'id': 'ASDASDASDASDASDASD'},
        'owner': {'address': '1234567890'},
        'tags': [
          {'name': 'Block-Start', 'value': '${range.start}'},
          {'name': 'Block-End', 'value': '${range.end}'},
          {'name': 'Drive-Id', 'value': 'asdasdasdasd'},
        ],
        'block': {
          'height': 100,
          'timestamp': DateTime.now().microsecondsSinceEpoch
        }
      },
    ),
    fakeSource: await fakeSnapshotSource(range),
    subRanges: r,
  );
}

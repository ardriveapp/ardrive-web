import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/segmented_gql_data.dart';
import 'package:ardrive/utils/snapshots/snapshot_drive_history.dart';
import 'package:ardrive/utils/snapshots/snapshot_item.dart';
import 'package:flutter_test/flutter_test.dart';

import 'snapshot_item_test.dart';

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
    test('returns a single stream if the sub-ranges are composable', () async {
      final fakeItems =
          composableRanges.map(fakeSnapshotItemFromRange).toList();
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
      final fakeItems =
          nonComposableRanges.map(fakeSnapshotItemFromRange).toList();
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

SnapshotItem fakeSnapshotItemFromRange(HeightRange r) {
  final range = heightRangeToRange(r);
  return SnapshotItem.fromStream(
    source: fakeNodesStream(range),
    blockStart: range.start,
    blockEnd: range.end,
    driveId: 'driveId',
    subRanges: r,
  );
}

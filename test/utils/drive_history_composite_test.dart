import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/utils/snapshots/drive_history_composite.dart';
import 'package:ardrive/utils/snapshots/gql_drive_history.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/segmented_gql_data.dart';
import 'package:ardrive/utils/snapshots/snapshot_drive_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/mocks.dart';
import 'snapshot_drive_history_test.dart';
import 'snapshot_test_helpers.dart';

void main() {
  group('DriveHistoryComposite class', () {
    final arweave = MockArweaveService();
    final List<Range> mockSubRanges = [
      Range(start: 11, end: 25),
      Range(start: 51, end: 98),
    ];

    setUp(() {
      when(
        () => arweave.getSegmentedTransactionsFromDrive(
          'DRIVE_ID',
          minBlockHeight: captureAny(named: 'minBlockHeight'),
          maxBlockHeight: captureAny(named: 'maxBlockHeight'),
          ownerAddress: any(named: 'ownerAddress'),
        ),
      ).thenAnswer(
        (invocation) => fakeNodesStream(
          Range(
            start: invocation.namedArguments[const Symbol('minBlockHeight')],
            end: invocation.namedArguments[const Symbol('maxBlockHeight')],
          ),
        )
            .map(
              (event) =>
                  DriveEntityHistory$Query$TransactionConnection$TransactionEdge()
                    ..node = event
                    ..cursor = 'mi cursor',
            )
            .map((event) => [event]),
      );

      when(() => arweave.getOwnerForDriveEntityWithId('DRIVE_ID')).thenAnswer(
        (invocation) => Future.value('owner'),
      );
    });

    test('constructor throws with invalid sub-ranges amount', () async {
      GQLDriveHistory gqlDriveHistory = GQLDriveHistory(
        arweave: arweave,
        driveId: 'DRIVE_ID',
        subRanges: HeightRange(rangeSegments: [
          Range(start: 0, end: 10),
          Range(start: 26, end: 50),
          Range(start: 99, end: 100),
        ]),
        ownerAddress: 'owner',
      );
      SnapshotDriveHistory snapshotDriveHistory = SnapshotDriveHistory(
        items: await Future.wait(mockSubRanges
            .map(
              (r) => fakeSnapshotItemFromRange(
                HeightRange(rangeSegments: [r]),
                arweave,
              ),
            )
            .toList()),
      );

      expect(
        () => DriveHistoryComposite(
          subRanges: HeightRange(rangeSegments: [
            Range(start: 0, end: 10),
            Range(start: 11, end: 20),
          ]),
          gqlDriveHistory: gqlDriveHistory,
          snapshotDriveHistory: snapshotDriveHistory,
        ),
        throwsA(isA<TooManySubRanges>()),
      );
      expect(
        () => DriveHistoryComposite(
          subRanges: HeightRange(rangeSegments: []),
          gqlDriveHistory: gqlDriveHistory,
          snapshotDriveHistory: snapshotDriveHistory,
        ),
        throwsA(isA<TooManySubRanges>()),
      );
    });

    test('getStreamForIndex returns a valid stream of nodes', () async {
      GQLDriveHistory gqlDriveHistory = GQLDriveHistory(
        arweave: arweave,
        driveId: 'DRIVE_ID',
        subRanges: HeightRange(rangeSegments: [
          Range(start: 0, end: 10),
          Range(start: 26, end: 50),
          Range(start: 99, end: 100),
        ]),
        ownerAddress: 'owner',
      );
      SnapshotDriveHistory snapshotDriveHistory = SnapshotDriveHistory(
        items: await Future.wait(mockSubRanges
            .map(
              (r) => fakeSnapshotItemFromRange(
                HeightRange(rangeSegments: [r]),
                arweave,
              ),
            )
            .toList()),
      );
      DriveHistoryComposite driveHistoryComposite = DriveHistoryComposite(
        subRanges: HeightRange(rangeSegments: [Range(start: 0, end: 100)]),
        gqlDriveHistory: gqlDriveHistory,
        snapshotDriveHistory: snapshotDriveHistory,
      );

      expect(driveHistoryComposite.subRanges.rangeSegments.length, 1);
      expect(driveHistoryComposite.currentIndex, -1);
      Stream stream = driveHistoryComposite.getNextStream();
      expect(driveHistoryComposite.currentIndex, 0);
      expect(await countStreamItems(stream), 101);

      expect(
        () => driveHistoryComposite.getNextStream(),
        throwsA(isA<SubRangeIndexOverflow>()),
      );
    });
  });
}

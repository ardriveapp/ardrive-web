import 'package:ardrive/sync/domain/models/drive_entity_history.dart';
import 'package:ardrive/utils/snapshots/gql_drive_history.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/segmented_gql_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';
import 'snapshot_test_helpers.dart';

void main() {
  group('GQLDriveHistory class', () {
    final arweave = MockArweaveService();

    // TODO: test the getter for the data when implemented

    setUp(() {
      when(
        () => arweave.getSegmentedTransactionsFromDrive(
          'DRIVE_ID',
          minBlockHeight: captureAny(named: 'minBlockHeight'),
          maxBlockHeight: captureAny(named: 'maxBlockHeight'),
          ownerAddress: 'owner',
          strategy: any(named: 'strategy'),
        ),
      ).thenAnswer(
        (invocation) => fakeNodesStream(
          Range(
            start: invocation.namedArguments[const Symbol('minBlockHeight')],
            end: invocation.namedArguments[const Symbol('maxBlockHeight')],
          ),
        ).map((event) => [event]),
      );

      when(() => arweave.getOwnerForDriveEntityWithId('DRIVE_ID')).thenAnswer(
        (invocation) => Future.value('owner'),
      );

      when(() => arweave.graphQLRetry).thenReturn(MockGraphQLRetry());
    });

    test('getStreamForIndex returns a valid stream of nodes', () async {
      GQLDriveHistory gqlDriveHistory = GQLDriveHistory(
        arweave: arweave,
        driveId: 'DRIVE_ID',
        subRanges: HeightRange(rangeSegments: [Range(start: 0, end: 10)]),
        ownerAddress: 'owner',
      );
      expect(gqlDriveHistory.subRanges.rangeSegments.length, 1);
      expect(gqlDriveHistory.currentIndex, -1);
      Stream<DriveEntityHistoryTransactionModel> stream =
          gqlDriveHistory.getNextStream();
      expect(gqlDriveHistory.currentIndex, 0);
      expect(await countStreamItems(stream), 11);

      expect(
        () => gqlDriveHistory.getNextStream(),
        throwsA(isA<SubRangeIndexOverflow>()),
      );

      gqlDriveHistory = GQLDriveHistory(
        arweave: arweave,
        driveId: 'DRIVE_ID',
        subRanges: HeightRange(rangeSegments: [
          Range(start: 0, end: 10),
          Range(start: 20, end: 30)
        ]),
        ownerAddress: 'owner',
      );
      expect(gqlDriveHistory.subRanges.rangeSegments.length, 2);
      expect(gqlDriveHistory.currentIndex, -1);
      stream = gqlDriveHistory.getNextStream();
      expect(gqlDriveHistory.currentIndex, 0);
      expect(await countStreamItems(stream), 11);
      stream = gqlDriveHistory.getNextStream();
      expect(gqlDriveHistory.currentIndex, 1);
      expect(await countStreamItems(stream), 11);

      expect(
        () => gqlDriveHistory.getNextStream(),
        throwsA(isA<SubRangeIndexOverflow>()),
      );
    });
  });
}

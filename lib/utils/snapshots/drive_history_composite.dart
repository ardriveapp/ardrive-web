import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/utils/snapshots/gql_drive_history.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/segmented_gql_data.dart';
import 'package:ardrive/utils/snapshots/snapshot_drive_history.dart';
import 'package:equatable/equatable.dart';

class DriveHistoryComposite implements SegmentedGQLData {
  final List<SegmentedGQLData> _subRangeToSnapshotItemMapping = [];
  final GQLDriveHistory _gqlDriveHistory;
  final SnapshotDriveHistory _snapshotDriveHistory;
  int _currentIndex = -1;

  DriveHistoryComposite({
    required this.subRanges,
    required GQLDriveHistory gqlDriveHistory,
    required SnapshotDriveHistory snapshotDriveHistory,
  })  : _gqlDriveHistory = gqlDriveHistory,
        _snapshotDriveHistory = snapshotDriveHistory {
    if (subRanges.rangeSegments.length != 1) {
      throw TooManySubRanges(amount: subRanges.rangeSegments.length);
    }

    _computeSubRanges();
  }

  @override
  final HeightRange subRanges;
  @override
  int get currentIndex => _currentIndex;

  void _computeSubRanges() {
    // flatterns the array of SnapshotItem::subRanges into a mapping of Range:Item
    final List<Range> allSubRanges = [
      ..._gqlDriveHistory.subRanges.rangeSegments,
      ..._snapshotDriveHistory.subRanges.rangeSegments,
    ]..sort((a, b) => a.start - b.start);
    final Map<Range, SegmentedGQLData> rangeToSnapshotItemMapping =
        Map.fromIterable(allSubRanges,
            key: (r) => r,
            value: (r) {
              final theRangeIsInSnapshotDriveHistory =
                  _snapshotDriveHistory.subRanges.rangeSegments.any(
                (element) => element == r,
              );
              return theRangeIsInSnapshotDriveHistory
                  ? _snapshotDriveHistory
                  : _gqlDriveHistory;
            });

    // appliies the union of height iteratively in order to compute _subRangeToSnapshotItemMapping
    for (Range range in allSubRanges) {
      SegmentedGQLData item = rangeToSnapshotItemMapping[range]!;
      _subRangeToSnapshotItemMapping.add(item);
    }
  }

  @override
  Stream<DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction>
      getNextStream() {
    _currentIndex++;
    if (currentIndex >= subRanges.rangeSegments.length) {
      throw SubRangeIndexOverflow(index: currentIndex);
    }

    return _getNextStream();
  }

  Stream<DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction>
      _getNextStream() async* {
    for (SegmentedGQLData source in _subRangeToSnapshotItemMapping) {
      yield* source.getNextStream();
    }
  }
}

class TooManySubRanges implements Exception, Equatable {
  final int _amount;
  const TooManySubRanges({required int amount}) : _amount = amount;

  @override
  List<Object?> get props => [_amount];

  @override
  final bool stringify = true;

  @override
  String toString() {
    return 'DriveHistoryComposite requires for a unique sub-range! (got: $_amount)';
  }
}

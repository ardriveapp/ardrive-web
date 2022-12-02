import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/segmented_gql_data.dart';
import 'package:ardrive/utils/snapshots/snapshot_item.dart';

class SnapshotDriveHistory implements SegmentedGQLData {
  final List<SnapshotItem> items;
  int _currentIndex = -1;
  final Map<Range, List<SnapshotItem>> _subRangeToSnapshotItemMapping = {};

  SnapshotDriveHistory({
    /// the list of SnapshorItems sorted by HEIGHT_DESC
    required this.items,
  }) {
    _computeSubRanges();
  }

  @override
  int get currentIndex => _currentIndex;

  @override
  HeightRange get subRanges => HeightRange(
        rangeSegments: _subRangeToSnapshotItemMapping.keys.toList(),
      );

  void _computeSubRanges() {
    // flatterns the array of SnapshotItem::subRanges into a mapping of Range:Item
    final Map<Range, SnapshotItem> rangeToSnapshotItemMapping = {};
    for (SnapshotItem item in items) {
      List<Range> subRanges = item.subRanges.rangeSegments;
      for (Range range in subRanges) {
        rangeToSnapshotItemMapping[range] = item;
      }
    }

    // an array of non-overlapping ranges within each SnapshotItem, sorted by height
    List<Range> allSubRanges = rangeToSnapshotItemMapping.keys.toList()
      ..sort((a, b) => a.start - b.start);

    // utilized to apply the union of HeightRange
    HeightRange auxiliarRange = HeightRange(rangeSegments: []);
    // tracks all (snapshot) items which composes certain sub-range of the SnapshotDriveHistory
    List<SnapshotItem> auxiliarItems = [];

    // appliies the union of height iteratively in order to compute _subRangeToSnapshotItemMapping
    for (Range range in allSubRanges) {
      SnapshotItem item = rangeToSnapshotItemMapping[range]!;
      HeightRange heightRange = HeightRange(rangeSegments: [range]);
      auxiliarRange = HeightRange.union(auxiliarRange, heightRange);

      if (auxiliarRange.rangeSegments.length == 2) {
        // the union resulted in two divergent sub-ranges, which indicates the beginning of a new sub-range
        final union = auxiliarRange.rangeSegments[0];

        // all (snapshot) items within the union are placed in the mapping
        _subRangeToSnapshotItemMapping[union] = auxiliarItems;

        // resets the auxiliar variables for the next iteration
        auxiliarItems = [item];
        auxiliarRange = HeightRange(
          rangeSegments: [auxiliarRange.rangeSegments[1]],
        );
      } else {
        // the union resulted in a single item; the current item is part of the sub-range
        auxiliarItems.add(item);
      }
    }

    if (auxiliarRange.rangeSegments.length == 1) {
      // the remaining items are the last ones added to the mapping
      _subRangeToSnapshotItemMapping[auxiliarRange.rangeSegments[0]] =
          auxiliarItems;
    }
  }

  @override
  Stream<DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction>
      getNextStream() {
    _currentIndex++;
    if (currentIndex >= subRanges.rangeSegments.length) {
      throw SubRangeIndexOverflow(index: currentIndex);
    }

    final stream = _getNextStream();
    return stream;
  }

  Stream<DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction>
      _getNextStream() async* {
    Range subRangeForIndex = subRanges.rangeSegments[currentIndex];
    List<SnapshotItem> itemsInRange =
        _subRangeToSnapshotItemMapping[subRangeForIndex]!;

    // reads the next stream of each item in the list and yields each node in order
    for (SnapshotItem item in itemsInRange) {
      final stream = item.getNextStream();
      yield* stream;
    }
  }
}

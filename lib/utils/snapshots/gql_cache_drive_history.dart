import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/utils/gql_nodes_cache.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/segmented_gql_data.dart';

// TODO: PE-2782: Abstract auto-generated GQL types
typedef DriveHistoryTransaction
    = DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction;

class GQLCacheDriveHistory extends SegmentedGQLData {
  final DriveID driveId;
  final GQLNodesCache cache;
  @override
  final HeightRange subRanges;

  int _currentIndex = -1;

  GQLCacheDriveHistory({
    required this.driveId,
    required this.subRanges,
    required this.cache,
  });

  @override
  int get currentIndex => _currentIndex;

  @override
  Stream<DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction>
      getNextStream() {
    _currentIndex++;
    if (currentIndex >= subRanges.rangeSegments.length) {
      throw SubRangeIndexOverflow(index: currentIndex);
    }

    return cache.asStreamOfNodes(driveId, ignoreLatestBlock: true);
  }
}

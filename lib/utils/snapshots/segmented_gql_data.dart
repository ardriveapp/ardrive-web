import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';

abstract class SegmentedGQLData {
  abstract final List<HeightRange> subRanges;
  Stream<DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction>
      getStreamForIndex(int index);
}

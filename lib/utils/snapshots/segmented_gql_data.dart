import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:equatable/equatable.dart';

abstract class SegmentedGQLData {
  abstract final HeightRange subRanges;
  Stream<DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction>
      getNextStream();
  int get currentIndex;
}

class SubRangeIndexOverflow implements Exception, Equatable {
  final int _index;
  const SubRangeIndexOverflow({required int index}) : _index = index;

  @override
  List<Object?> get props => [_index];

  @override
  final bool stringify = true;

  @override
  String toString() {
    return 'Segmented GQL data index overflow! ($_index)';
  }
}

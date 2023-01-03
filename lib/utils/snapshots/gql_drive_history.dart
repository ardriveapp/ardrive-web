import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/segmented_gql_data.dart';

import '../../services/arweave/arweave_service.dart';

class GQLDriveHistory implements SegmentedGQLData {
  final DriveID driveId;

  int _currentIndex = -1;
  final ArweaveService _arweave;

  @override
  final HeightRange subRanges;
  @override
  int get currentIndex => _currentIndex;

  GQLDriveHistory({
    required this.subRanges,
    required ArweaveService arweave,
    required this.driveId,
  }) : _arweave = arweave;

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
    Range subRangeForIndex = subRanges.rangeSegments[currentIndex];

    final txsStream = _arweave.getSegmentedTransactionsFromDrive(
      driveId,
      minBlockHeight: subRangeForIndex.start,
      maxBlockHeight: subRangeForIndex.end,
    );

    await for (final multipleEdges in txsStream) {
      for (final edge in multipleEdges) {
        yield edge.node;
      }
    }
  }
}

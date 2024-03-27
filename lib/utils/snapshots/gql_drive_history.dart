import 'package:ardrive/services/arweave/get_segmented_transaction_from_drive_strategy.dart';
import 'package:ardrive/sync/domain/models/drive_entity_history.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/segmented_gql_data.dart';
import 'package:ardrive_utils/ardrive_utils.dart';

import '../../services/arweave/arweave_service.dart';

class GQLDriveHistory implements SegmentedGQLData {
  final DriveID driveId;
  final String ownerAddress;

  int _txCount = 0;

  int _currentIndex = -1;
  final ArweaveService _arweave;

  @override
  final HeightRange subRanges;
  @override
  int get currentIndex => _currentIndex;

  int get txCount => _txCount;

  GQLDriveHistory({
    required this.subRanges,
    required ArweaveService arweave,
    required this.driveId,
    required this.ownerAddress,
  }) : _arweave = arweave;

  @override
  Stream<DriveEntityHistoryTransactionModel> getNextStream() {
    _currentIndex++;
    if (currentIndex >= subRanges.rangeSegments.length) {
      throw SubRangeIndexOverflow(index: currentIndex);
    }

    return _getNextStream();
  }

  Stream<DriveEntityHistoryTransactionModel> _getNextStream() async* {
    Range subRangeForIndex = subRanges.rangeSegments[currentIndex];

    final txsStream = _arweave.getSegmentedTransactionsFromDrive(
      driveId,
      minBlockHeight: subRangeForIndex.start,
      maxBlockHeight: subRangeForIndex.end,
      ownerAddress: ownerAddress,
      strategy: GetSegmentedTransactionFromDriveFilteringByEntityTypeStrategy(
        _arweave.graphQLRetry,
      ),
    );

    await for (final multipleEdges in txsStream) {
      for (final edge in multipleEdges) {
        _txCount++;
        yield DriveEntityHistoryTransactionModel(
          transactionCommonMixin: edge.transactionCommonMixin,
          cursor: edge.cursor,
        );
      }
    }
  }
}

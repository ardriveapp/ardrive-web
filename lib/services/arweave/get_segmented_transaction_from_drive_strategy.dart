import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/models/drive_entity_history.dart';
import 'package:ardrive/utils/arfs_txs_filter.dart';
import 'package:ardrive/utils/graphql_retry.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/snapshots/snapshot_item_to_be_created.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:collection/collection.dart';

/// Strategy to get the transactions from the drive
abstract class GetSegmentedTransactionFromDriveStrategy {
  Stream<List<DriveEntityHistoryTransactionModel>>
      getSegmentedTransactionFromDrive(
    String driveId, {
    required String ownerAddress,
    int? minBlockHeight,
    int? maxBlockHeight,
  });
}

/// Gets the transactions from the drive, without any `Entity-Type` filtering,
/// returning all the transactions ordered by block height.
class GetSegmentedTransactionFromDriveWithoutEntityTypeFilterStrategy
    implements GetSegmentedTransactionFromDriveStrategy {
  final GraphQLRetry _graphQLRetry;

  const GetSegmentedTransactionFromDriveWithoutEntityTypeFilterStrategy(
      this._graphQLRetry);

  @override
  Stream<List<DriveEntityHistoryTransactionModel>>
      getSegmentedTransactionFromDrive(
    String driveId, {
    required String ownerAddress,
    int? minBlockHeight,
    int? maxBlockHeight,
  }) async* {
    yield* _getSegmentedTransactionWithoutFilter(
      driveId: driveId,
      ownerAddress: ownerAddress,
      graphQLRetry: _graphQLRetry,
    );
  }

  Stream<List<DriveEntityHistoryTransactionModel>>
      _getSegmentedTransactionWithoutFilter({
    required String driveId,
    required String ownerAddress,
    int? minBlockHeight,
    int? maxBlockHeight,
    required GraphQLRetry graphQLRetry,
  }) async* {
    String? cursor;
    while (true) {
      final queryResult = await graphQLRetry.execute(
        DriveEntityHistoryWithoutEntityTypeFilterQuery(
          variables: DriveEntityHistoryWithoutEntityTypeFilterArguments(
            driveId: driveId,
            minBlockHeight: minBlockHeight,
            maxBlockHeight: maxBlockHeight,
            after: cursor,
            ownerAddress: ownerAddress,
          ),
        ),
      );

      if (queryResult.data == null) {
        logger.w('No data in the query result');
        break;
      }

      final transactions = queryResult.data!.transactions.edges
          .map((e) => DriveEntityHistoryTransactionModel(
              transactionCommonMixin: e.node, cursor: e.cursor))
          .where((edge) => _isSupportedArFSVersion(edge.transactionCommonMixin))
          .toList();
      yield transactions;

      cursor = transactions.isNotEmpty ? transactions.last.cursor : null;

      if (!queryResult.data!.transactions.pageInfo.hasNextPage) {
        break;
      }
    }
  }
}

/// Gets the transactions from the drive, filtering by `Entity-Type` tag.
///
/// This strategy is used to get the transactions for the `Folder` and `File` entities.
/// It first gets the transactions for the `Folder` entity, and then for the `File` entity.
class GetSegmentedTransactionFromDriveFilteringByEntityTypeStrategy
    implements GetSegmentedTransactionFromDriveStrategy {
  final GraphQLRetry _graphQLRetry;

  GetSegmentedTransactionFromDriveFilteringByEntityTypeStrategy(
    this._graphQLRetry,
  );

  @override
  Stream<List<DriveEntityHistoryTransactionModel>>
      getSegmentedTransactionFromDrive(
    String driveId, {
    required String ownerAddress,
    int? minBlockHeight,
    int? maxBlockHeight,
  }) async* {
    yield* _getSegmentedTransaction(
      driveId: driveId,
      entityType: EntityTypeTag.drive,
      ownerAddress: ownerAddress,
      minBlockHeight: minBlockHeight,
      maxBlockHeight: maxBlockHeight,
      graphQLRetry: _graphQLRetry,
    );
    yield* _getSegmentedTransaction(
      driveId: driveId,
      entityType: EntityTypeTag.folder,
      ownerAddress: ownerAddress,
      minBlockHeight: minBlockHeight,
      maxBlockHeight: maxBlockHeight,
      graphQLRetry: _graphQLRetry,
    );
    yield* _getSegmentedTransaction(
      driveId: driveId,
      entityType: EntityTypeTag.file,
      ownerAddress: ownerAddress,
      minBlockHeight: minBlockHeight,
      maxBlockHeight: maxBlockHeight,
      graphQLRetry: _graphQLRetry,
    );
  }

  Stream<List<DriveEntityHistoryTransactionModel>> _getSegmentedTransaction({
    required String driveId,
    required String entityType,
    required String ownerAddress,
    int? minBlockHeight,
    int? maxBlockHeight,
    required GraphQLRetry graphQLRetry,
  }) async* {
    String? cursor;
    while (true) {
      final queryResult = await graphQLRetry.execute(
        DriveEntityHistoryQuery(
          variables: DriveEntityHistoryArguments(
            driveId: driveId,
            minBlockHeight: minBlockHeight,
            maxBlockHeight: maxBlockHeight,
            after: cursor,
            ownerAddress: ownerAddress,
            entityType: entityType,
          ),
        ),
      );

      if (queryResult.data == null) {
        logger.w('No data in the query result');
        break;
      }

      final transactions = queryResult.data!.transactions.edges
          .where((edge) => _isSupportedArFSVersion(edge.node))
          .map((e) => DriveEntityHistoryTransactionModel(
                transactionCommonMixin: e.node,
                cursor: e.cursor,
              ))
          .toList();

      yield transactions;

      cursor = transactions.isNotEmpty ? transactions.last.cursor : null;

      if (!queryResult.data!.transactions.pageInfo.hasNextPage) {
        break;
      }
    }
  }
}

bool _isSupportedArFSVersion(TransactionCommonMixin node) {
  final arfsTag =
      node.tags.firstWhereOrNull((tag) => tag.name == EntityTag.arFs);
  return arfsTag != null && supportedArFSVersionsSet.contains(arfsTag.value);
}

DriveHistoryTransactionEdge parseDriveHistoryTransactionEdge(
  DriveHistoryWithoutEntityTypeFilterTransactionEdge edge,
) {
  return DriveHistoryTransactionEdge.fromJson({
    'cursor': edge.cursor,
    'node': edge.node.toJson(),
  });
}

import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';

class DriveEntityHistoryTransactionModel {
  final TransactionCommonMixin transactionCommonMixin;
  final String? cursor;

  DriveEntityHistoryTransactionModel({
    required this.transactionCommonMixin,
    this.cursor,
  });
}

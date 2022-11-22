part of 'package:ardrive/blocs/sync/sync_cubit.dart';

Future<void> _updateTransactionStatuses({
  required DriveDao driveDao,
  required ArweaveService arweave,
}) async {
  final pendingTxMap = {
    for (final tx in await driveDao.pendingTransactions().get()) tx.id: tx,
  };

  final length = pendingTxMap.length;
  final list = pendingTxMap.keys.toList();

  // Thats was discovered by tests at profile mode.
  // TODO(@thiagocarvalhodev): Revisit
  const page = 5000;

  for (var i = 0; i < length / page; i++) {
    final confirmations = <String?, int>{};
    final currentPage = <String>[];

    /// Mounts the list to be iterated
    for (var j = i * page; j < ((i + 1) * page); j++) {
      if (j >= length) {
        break;
      }
      currentPage.add(list[j]);
    }

    final map = await arweave.getTransactionConfirmations(currentPage.toList());

    map.forEach((key, value) {
      confirmations.putIfAbsent(key, () => value);
    });

    await driveDao.transaction(() async {
      for (final txId in currentPage) {
        final txConfirmed =
            confirmations[txId]! >= kRequiredTxConfirmationCount;
        final txNotFound = confirmations[txId]! < 0;

        String? txStatus;

        DateTime? transactionDateCreated;

        if (pendingTxMap[txId]!.transactionDateCreated != null) {
          transactionDateCreated = pendingTxMap[txId]!.transactionDateCreated!;
        } else {
          transactionDateCreated = await _getDateCreatedByDataTx(
            driveDao: driveDao,
            dataTx: txId,
          );
        }

        if (txConfirmed) {
          txStatus = TransactionStatus.confirmed;
        } else if (txNotFound) {
          // Only mark transactions as failed if they are unconfirmed for over 45 minutes
          // as the transaction might not be queryable for right after it was created.
          final abovePendingThreshold = DateTime.now()
                  .difference(pendingTxMap[txId]!.dateCreated)
                  .inMinutes >
              kRequiredTxConfirmationPendingThreshold;

          // Assume that data tx that weren't mined up to a maximum of
          // `_pendingWaitTime` was failed.
          if (abovePendingThreshold ||
              _isOverThePendingTime(transactionDateCreated)) {
            txStatus = TransactionStatus.failed;
          }
        }
        if (txStatus != null) {
          await driveDao.writeToTransaction(
            NetworkTransactionsCompanion(
              transactionDateCreated: Value(transactionDateCreated),
              id: Value(txId),
              status: Value(txStatus),
            ),
          );
        }
      }
    });
    await Future.delayed(const Duration(milliseconds: 200));
  }
}

bool _isOverThePendingTime(DateTime? transactionCreatedDate) {
  // If don't have the date information we cannot assume that is over the pending time
  if (transactionCreatedDate == null) {
    return false;
  }

  return DateTime.now().isAfter(transactionCreatedDate.add(_pendingWaitTime));
}

Future<DateTime?> _getDateCreatedByDataTx({
  required DriveDao driveDao,
  required String dataTx,
}) async {
  final rev = await driveDao.fileRevisionByDataTx(tx: dataTx).get();

  // no file found
  if (rev.isEmpty) {
    return null;
  }

  return rev.first.dateCreated;
}

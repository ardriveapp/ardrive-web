import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/models/enums.dart';
import 'package:drift/drift.dart';

List<NetworkTransactionsCompanion> createNetworkTransactionsCompanionsForDrives(
  List<DriveRevisionsCompanion> newRevisions,
) {
  return newRevisions
      .map(
        (rev) => NetworkTransactionsCompanion.insert(
          transactionDateCreated: rev.dateCreated,
          id: rev.metadataTxId.value,
          status: const Value(TransactionStatus.confirmed),
        ),
      )
      .toList();
}

List<NetworkTransactionsCompanion> createNetworkTransactionsCompanionsForFiles(
  List<FileRevisionsCompanion> newRevisions,
) {
  return newRevisions
      .expand(
        (rev) => [
          NetworkTransactionsCompanion.insert(
            transactionDateCreated: rev.dateCreated,
            id: rev.metadataTxId.value,
            status: const Value(TransactionStatus.confirmed),
          ),
          // We cannot be sure that the data tx of files have been mined
          // so we'll mark it as pending initially.
          NetworkTransactionsCompanion.insert(
            transactionDateCreated: rev.dateCreated,
            id: rev.dataTxId.value,
            status: const Value(TransactionStatus.pending),
          ),
        ],
      )
      .toList();
}

List<NetworkTransactionsCompanion>
    createNetworkTransactionsCompanionsForFolders(
  List<FolderRevisionsCompanion> newRevisions,
) {
  return newRevisions
      .map(
        (rev) => NetworkTransactionsCompanion.insert(
          transactionDateCreated: rev.dateCreated,
          id: rev.metadataTxId.value,
          status: const Value(TransactionStatus.confirmed),
        ),
      )
      .toList();
}

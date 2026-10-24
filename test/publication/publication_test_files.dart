import 'package:ardrive/models/models.dart';
import 'package:drift/drift.dart' show Value;

/// Writes a file as a snapshot import leaves one: its entry, one revision and
/// that revision's two transactions, with [status]. The explorer lists a
/// file only through its latest revision's transactions.
Future<void> insertPublicationFile(
  Database db, {
  required String driveId,
  required String id,
  required String name,
  required String parentFolderId,
  int size = 1,
  bool hidden = false,
  String status = TransactionStatus.confirmed,
}) async {
  final metadataTxId = '${id}Meta';
  final dataTxId = '${id}Data';
  for (final tx in [metadataTxId, dataTxId]) {
    await db.into(db.networkTransactions).insert(
          NetworkTransactionsCompanion.insert(id: tx, status: Value(status)),
        );
  }
  await db.into(db.fileRevisions).insert(FileRevisionsCompanion.insert(
        fileId: id,
        driveId: driveId,
        name: name,
        parentFolderId: parentFolderId,
        size: size,
        lastModifiedDate: DateTime.utc(2026),
        metadataTxId: metadataTxId,
        dataTxId: dataTxId,
        action: RevisionAction.create,
        isHidden: Value(hidden),
      ));
  await db.into(db.fileEntries).insert(FileEntriesCompanion.insert(
        id: id,
        driveId: driveId,
        parentFolderId: parentFolderId,
        name: name,
        dataTxId: dataTxId,
        size: size,
        lastModifiedDate: DateTime.utc(2026),
        isHidden: Value(hidden),
        path: '',
      ));
}

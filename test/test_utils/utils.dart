import 'dart:convert';
import 'dart:io' if (dart.library.html) 'dart:html';
import 'dart:math';

import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

export 'matchers.dart';
export 'mocks.dart';
export 'test_wallet.dart';

import 'test_wallet.dart';

Database getTestDb() => Database(NativeDatabase.memory());

Future<void> addTestFilesToDb(
  Database db, {
  required String driveId,
  required String rootFolderId,
  required String nestedFolderId,
  required int emptyNestedFolderCount,
  required String emptyNestedFolderIdPrefix,
  required int rootFolderFileCount,
  required int nestedFolderFileCount,
  int seed = 0,
}) async {
  await db.batch((batch) {
    // Default date
    final defaultDate = DateTime(2017, 9, 7, 17, 30);
    // Create fake drive for test
    batch.insert(
      db.drives,
      DrivesCompanion.insert(
        id: driveId,
        rootFolderId: rootFolderId,
        ownerAddress: 'fake-owner-address',
        name: 'fake-drive-name',
        privacy: DrivePrivacyTag.public,
      ),
    );
    // Create fake root folder for drive and sub folders
    batch.insertAll(
      db.folderEntries,
      [
        FolderEntriesCompanion.insert(
          id: rootFolderId,
          driveId: driveId,
          name: 'fake-drive-name',
          isHidden: const Value(false),
          path: '',
        ),
        FolderEntriesCompanion.insert(
          id: nestedFolderId,
          driveId: driveId,
          parentFolderId: Value(rootFolderId),
          name: nestedFolderId,
          isHidden: const Value(false),
          path: '',
        ),
        ...List.generate(
          emptyNestedFolderCount,
          (i) {
            final folderId = '$emptyNestedFolderIdPrefix$i';
            return FolderEntriesCompanion.insert(
              id: folderId,
              driveId: driveId,
              parentFolderId: Value(rootFolderId),
              name: folderId,
              isHidden: const Value(false),
              path: '',
            );
          },
        )..shuffle(Random(0)),
      ],
    );
    // Insert fake files
    batch.insertAll(
      db.fileEntries,
      [
        ...List.generate(
          rootFolderFileCount,
          (i) {
            final fileId = '$rootFolderId$i';
            return FileEntriesCompanion.insert(
              id: fileId,
              driveId: driveId,
              parentFolderId: rootFolderId,
              name: fileId,
              dataTxId: '${fileId}Data',
              size: 500,
              dateCreated: Value(defaultDate),
              lastModifiedDate: defaultDate,
              dataContentType: const Value(''),
              isHidden: const Value(false),
              path: '',
            );
          },
        )..shuffle(Random(0)),
        ...List.generate(
          nestedFolderFileCount,
          (i) {
            final fileId = '$nestedFolderId$i';
            return FileEntriesCompanion.insert(
              id: fileId,
              driveId: driveId,
              parentFolderId: nestedFolderId,
              name: fileId,
              dataTxId: '${fileId}Data',
              size: 500,
              dateCreated: Value(defaultDate),
              lastModifiedDate: defaultDate,
              dataContentType: const Value(''),
              isHidden: const Value(false),
              path: '',
            );
          },
        )..shuffle(Random(0)),
      ],
    );
    // Insert fake file revisions
    batch.insertAll(
      db.fileRevisions,
      [
        ...List.generate(
          rootFolderFileCount,
          (i) {
            final fileId = '$rootFolderId$i';
            return FileRevisionsCompanion.insert(
              fileId: fileId,
              driveId: driveId,
              parentFolderId: rootFolderId,
              name: fileId,
              metadataTxId: '${fileId}Meta',
              action: RevisionAction.create,
              dataTxId: '${fileId}Data',
              size: 500,
              dateCreated: Value(defaultDate),
              lastModifiedDate: defaultDate,
              dataContentType: const Value(''),
              isHidden: const Value(false),
            );
          },
        )..shuffle(Random(0)),
        ...List.generate(
          nestedFolderFileCount,
          (i) {
            final fileId = '$nestedFolderId$i';
            return FileRevisionsCompanion.insert(
              fileId: fileId,
              driveId: driveId,
              parentFolderId: nestedFolderId,
              name: fileId,
              dataTxId: '${fileId}Meta',
              metadataTxId: '${fileId}Data',
              action: RevisionAction.create,
              size: 500,
              dateCreated: Value(defaultDate),
              lastModifiedDate: defaultDate,
              dataContentType: const Value(''),
              isHidden: const Value(false),
            );
          },
        )..shuffle(Random(0)),
      ],
    );
    // Insert fake metadata and data transactions
    batch.insertAll(
      db.networkTransactions,
      [
        ...List.generate(
          rootFolderFileCount,
          (i) {
            final fileId = '$rootFolderId$i';
            return NetworkTransactionsCompanion.insert(
              id: '${fileId}Meta',
              status: const Value(TransactionStatus.confirmed),
              dateCreated: Value(defaultDate),
            );
          },
        )..shuffle(Random(0)),
        ...List.generate(
          rootFolderFileCount,
          (i) {
            final fileId = '$rootFolderId$i';
            return NetworkTransactionsCompanion.insert(
              id: '${fileId}Data',
              status: const Value(TransactionStatus.confirmed),
              dateCreated: Value(defaultDate),
            );
          },
        )..shuffle(Random(0)),
        ...List.generate(
          nestedFolderFileCount,
          (i) {
            final fileId = '$nestedFolderId$i';
            return NetworkTransactionsCompanion.insert(
              id: '${fileId}Meta',
              status: const Value(TransactionStatus.confirmed),
              dateCreated: Value(defaultDate),
            );
          },
        )..shuffle(Random(0)),
        ...List.generate(
          nestedFolderFileCount,
          (i) {
            final fileId = '$nestedFolderId$i';
            return NetworkTransactionsCompanion.insert(
              id: '${fileId}Data',
              status: const Value(TransactionStatus.confirmed),
              dateCreated: Value(defaultDate),
            );
          },
        )..shuffle(Random(0)),
      ],
    );
  });
}

/// Writes a folder revision for each of [folderIds], the way sync does when a
/// folder's real metadata lands.
///
/// [addTestFilesToDb] writes a revision for every file it inserts but none for
/// its folders, so to anything that tells a chain-derived row from one this
/// client invented - the drive state export, `DriveDetailCubit`'s
/// never-synced check - its folders read as local stand-ins. Call this to say
/// the folders synced.
/// Folder revisions as a sync writes them: the metadata transaction is
/// `confirmed`, because a sync only ever reads metadata that is on chain.
///
/// `insertFolderRevision` is the path a *local* change takes and marks it
/// `pending`, so the status is set afterwards rather than left as that path's.
Future<void> addFolderRevisionsToDb(
  Database db, {
  required String driveId,
  required Iterable<String> folderIds,
  DateTime? dateCreated,
}) async {
  for (final folderId in folderIds) {
    await db.driveDao.insertFolderRevision(
      FolderRevisionsCompanion.insert(
        folderId: folderId,
        driveId: driveId,
        name: folderId,
        metadataTxId: '${folderId}Meta',
        action: RevisionAction.create,
        dateCreated: Value(dateCreated ?? DateTime(2017, 9, 7, 17, 30)),
      ),
    );
    await db.into(db.networkTransactions).insertOnConflictUpdate(
          NetworkTransactionsCompanion.insert(
            id: '${folderId}Meta',
            status: const Value(TransactionStatus.confirmed),
          ),
        );
  }
}

Future<Transaction> getTestTransaction(String path) async =>
    Transaction.fromJson(json.decode(await File(path).readAsString()));

Future<DataItem> getTestDataItem(String path) async {
  final wallet = getTestWallet();
  final dataItem = DataItem.withJsonData(
    owner: await wallet.getOwner(),
    data: json.decode(await File(path).readAsString()),
  );
  await dataItem.sign(ArweaveSigner(getTestWallet()));
  return dataItem;
}

User getTestUser() => User(
      password: 'password',
      wallet: getTestWallet(),
      walletAddress: 'test-wallet-address',
      walletBalance: BigInt.from(1000),
      cipherKey: SecretKey([1, 2, 3, 4, 5]),
      profileType: ProfileType.arConnect,
      ioTokens: '100',
      errorFetchingIOTokens: false,
    );

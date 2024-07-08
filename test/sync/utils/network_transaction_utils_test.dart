import 'package:ardrive/models/models.dart';
import 'package:ardrive/sync/utils/network_transaction_utils.dart';
import 'package:drift/drift.dart';
import 'package:test/test.dart';

void main() {
  group('createNetworkTransactionsCompanionsForDrives tests', () {
    test('should return empty list when input is empty', () {
      final result = createNetworkTransactionsCompanionsForDrives([]);
      expect(result, isEmpty);
    });

    test(
        'should return list of NetworkTransactionsCompanion when input is not empty',
        () {
      final revisions = [
        DriveRevisionsCompanion(
          dateCreated: Value(DateTime.now()),
          metadataTxId: const Value('some_tx_id'),
          // add other necessary fields here
        ),
      ];

      final result = createNetworkTransactionsCompanionsForDrives(revisions);

      expect(result, isNotEmpty);
      expect(result.length, revisions.length);
      expect(result[0].transactionDateCreated, revisions[0].dateCreated);
      expect(result[0].id, Value(revisions[0].metadataTxId.value));
      expect(result[0].status, const Value(TransactionStatus.confirmed));
    });

    test('should correctly map multiple DriveRevisionsCompanion objects', () {
      final revisions = [
        // Add multiple DriveRevisionsCompanion objects here
        DriveRevisionsCompanion(
          dateCreated: Value(DateTime.now().subtract(const Duration(days: 1))),
          metadataTxId: const Value('tx_id_1'),
          // add other necessary fields here
        ),
        DriveRevisionsCompanion(
          dateCreated: Value(DateTime.now()),
          metadataTxId: const Value('tx_id_2'),
          // add other necessary fields here
        ),
      ];

      final result = createNetworkTransactionsCompanionsForDrives(revisions);

      expect(result.length, revisions.length);
      for (int i = 0; i < revisions.length; i++) {
        expect(result[i].transactionDateCreated, revisions[i].dateCreated);
        expect(result[i].id, Value(revisions[i].metadataTxId.value));
        expect(result[i].status, const Value(TransactionStatus.confirmed));
      }
    });
  });
  group('createNetworkTransactionsCompanionsForFiles tests', () {
    test('should return empty list when input is empty', () {
      final result = createNetworkTransactionsCompanionsForFiles([]);
      expect(result, isEmpty);
    });

    test('should return non-empty list when input is not empty', () {
      final revisions = [
        FileRevisionsCompanion(
          dateCreated: Value(DateTime.now()),
          metadataTxId: const Value('metadata_tx_id'),
          dataTxId: const Value('data_tx_id'),
          // add other necessary fields here
        ),
      ];

      final result = createNetworkTransactionsCompanionsForFiles(revisions);

      expect(result, isNotEmpty);
      expect(
          result.length,
          revisions.length *
              2); // Expect twice the number because of two transactions per revision
      expect(result[0].transactionDateCreated, revisions[0].dateCreated);
      expect(result[0].id, Value(revisions[0].metadataTxId.value));
      expect(result[0].status, const Value(TransactionStatus.confirmed));
      expect(result[1].transactionDateCreated, revisions[0].dateCreated);
      expect(result[1].id, Value(revisions[0].dataTxId.value));
      expect(result[1].status, const Value(TransactionStatus.pending));
    });

    test('should correctly map multiple FileRevisionsCompanion objects', () {
      final revisions = [
        FileRevisionsCompanion(
          dateCreated: Value(DateTime.now().subtract(const Duration(days: 1))),
          metadataTxId: const Value('metadata_tx_id_1'),
          dataTxId: const Value('data_tx_id_1'),
          // add other necessary fields here
        ),
        FileRevisionsCompanion(
          dateCreated: Value(DateTime.now()),
          metadataTxId: const Value('metadata_tx_id_2'),
          dataTxId: const Value('data_tx_id_2'),
          // add other necessary fields here
        ),
      ];

      final result = createNetworkTransactionsCompanionsForFiles(revisions);

      expect(
          result.length,
          revisions.length *
              2); // Expect twice the number because of two transactions per revision
      for (int i = 0; i < revisions.length; i++) {
        // Checking the 'confirmed' transaction for metadata
        expect(result[i * 2].transactionDateCreated, revisions[i].dateCreated);
        expect(result[i * 2].id, Value(revisions[i].metadataTxId.value));
        expect(result[i * 2].status, const Value(TransactionStatus.confirmed));

        // Checking the 'pending' transaction for data
        expect(
            result[i * 2 + 1].transactionDateCreated, revisions[i].dateCreated);
        expect(result[i * 2 + 1].id, Value(revisions[i].dataTxId.value));
        expect(
            result[i * 2 + 1].status, const Value(TransactionStatus.pending));
      }
    });
  });
  group('createNetworkTransactionsCompanionsForFolders tests', () {
    test('should return empty list when input is empty', () {
      final result = createNetworkTransactionsCompanionsForFolders([]);
      expect(result, isEmpty);
    });

    test(
        'should return list of NetworkTransactionsCompanion when input is not empty',
        () {
      final revisions = [
        FolderRevisionsCompanion(
          dateCreated: Value(DateTime.now()),
          metadataTxId: const Value('some_tx_id'),
          // Add other necessary fields here
        ),
      ];

      final result = createNetworkTransactionsCompanionsForFolders(revisions);

      expect(result, isNotEmpty);
      expect(result.length, revisions.length);
      expect(result[0].transactionDateCreated, revisions[0].dateCreated);
      expect(result[0].id, Value(revisions[0].metadataTxId.value));
      expect(result[0].status, const Value(TransactionStatus.confirmed));
    });

    test('should correctly map multiple FolderRevisionsCompanion objects', () {
      final revisions = [
        // Add multiple FolderRevisionsCompanion objects here
        FolderRevisionsCompanion(
          dateCreated: Value(DateTime.now().subtract(const Duration(days: 1))),
          metadataTxId: const Value('tx_id_1'),
          // Add other necessary fields here
        ),
        FolderRevisionsCompanion(
          dateCreated: Value(DateTime.now()),
          metadataTxId: const Value('tx_id_2'),
          // Add other necessary fields here
        ),
      ];

      final result = createNetworkTransactionsCompanionsForFolders(revisions);

      expect(result.length, revisions.length);
      for (int i = 0; i < revisions.length; i++) {
        expect(result[i].transactionDateCreated, revisions[i].dateCreated);
        expect(result[i].id, Value(revisions[i].metadataTxId.value));
        expect(result[i].status, const Value(TransactionStatus.confirmed));
      }
    });
  });
}

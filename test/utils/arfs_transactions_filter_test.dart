import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/utils/arfs_transactions_filter.dart';
import 'package:flutter_test/flutter_test.dart';

DriveEntityHistory$Query$TransactionConnection$TransactionEdge stubTransaction({
  required String? arFsVersion,
}) {
  return DriveEntityHistory$Query$TransactionConnection$TransactionEdge
      .fromJson({
    'node': {
      'id': 'txId',
      'bundledIn': {'id': 'ASDASDASDASDASDASD'},
      'owner': {'address': '1234567890'},
      'tags': [
        if (arFsVersion != null)
          {
            'name': 'ArFS',
            'value': arFsVersion,
          },
      ],
      'block': {
        'height': 1,
        'timestamp': 100,
      }
    },
    'cursor': 'cursor',
  });
}

void main() {
  group('arFsTransactionsFilter', () {
    test('filters out transactions with no ArFS tags on it', () {
      final transactionsWithNoArFsTag = [
        stubTransaction(arFsVersion: null),
      ];

      final filteredTransactions =
          transactionsWithNoArFsTag.where(arFsTransactionsFilter).toList();

      expect(filteredTransactions, isEmpty);
    });

    test('preserves transactions with valid values', () {
      final transactionsWithValidArFsTag = [
        stubTransaction(arFsVersion: '0.10'),
        stubTransaction(arFsVersion: '0.11'),
        stubTransaction(arFsVersion: '0.12'),
      ];

      final filteredTransactions =
          transactionsWithValidArFsTag.where(arFsTransactionsFilter).toList();

      expect(filteredTransactions, transactionsWithValidArFsTag);
    });

    test('filters out transactions with invalid values', () {
      final transactionsWithInvalidArFsTag = [
        stubTransaction(arFsVersion: '0.13'),
        stubTransaction(arFsVersion: '0.14'),
        stubTransaction(arFsVersion: '0.15'),
      ];

      final filteredTransactions =
          transactionsWithInvalidArFsTag.where(arFsTransactionsFilter).toList();

      expect(filteredTransactions, isEmpty);
    });
  });
}

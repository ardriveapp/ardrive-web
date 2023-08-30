import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/utils/arfs_txs_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const arFsTagName = 'ArFS';

  group('doesTagsContainValidArFSVersion method', () {
    test('returns true for transactions containing the correct versions', () {
      final tags = [
        TransactionCommonMixin$Tag.fromJson({
          'name': arFsTagName,
          'value': '0.10',
        }),
        TransactionCommonMixin$Tag.fromJson({
          'name': arFsTagName,
          'value': '0.11',
        }),
        TransactionCommonMixin$Tag.fromJson({
          'name': arFsTagName,
          'value': '0.12',
        }),
        TransactionCommonMixin$Tag.fromJson({
          'name': arFsTagName,
          'value': '0.13',
        }),
      ];

      for (final tag in tags) {
        expect(doesTagsContainValidArFSVersion([tag]), true);
      }
    });

    test('returns false for transactions containing the incorrect versions',
        () {
      final tags = [
        TransactionCommonMixin$Tag.fromJson({
          'name': arFsTagName,
          'value': '0.9',
        }),
        TransactionCommonMixin$Tag.fromJson({
          'name': arFsTagName,
          'value': '0.14',
        }),
        TransactionCommonMixin$Tag.fromJson({
          'name': arFsTagName,
          'value': '0.15',
        }),
        TransactionCommonMixin$Tag.fromJson({
          'name': arFsTagName,
          'value': '0.16',
        }),
        TransactionCommonMixin$Tag.fromJson({
          'name': arFsTagName,
          'value': 'Supercalifragilisticoespialidoso',
        }),
      ];

      for (final tag in tags) {
        expect(doesTagsContainValidArFSVersion([tag]), false);
      }

      expect(doesTagsContainValidArFSVersion([]), false);
    });
  });
}

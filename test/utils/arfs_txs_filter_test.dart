import 'package:ardrive/utils/arfs_txs_filter.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const arFsTagName = 'ArFS';

  group('doesTagsContainValidArFSVersion method', () {
    test('returns true for transactions containing the correct versions', () {
      final tags = [
        Tag(arFsTagName, '0.10'),
        Tag(arFsTagName, '0.11'),
        Tag(arFsTagName, '0.12'),
        Tag(arFsTagName, '0.13'),
        Tag(arFsTagName, '0.14'),
        Tag(arFsTagName, '0.15'),
      ];

      for (final tag in tags) {
        expect(doesTagsContainValidArFSVersion([tag]), true);
      }
    });

    test('returns false for transactions containing the incorrect versions',
        () {
      final tags = [
        Tag(arFsTagName, '0.9'),
        Tag(arFsTagName, '0.16'),
        Tag(arFsTagName, 'Supercalifragilisticoespialidoso'),
      ];

      for (final tag in tags) {
        expect(doesTagsContainValidArFSVersion([tag]), false);
      }

      expect(doesTagsContainValidArFSVersion([]), false);
    });
  });
}

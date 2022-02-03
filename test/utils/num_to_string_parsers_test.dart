import 'dart:math';

import 'package:ardrive/utils/num_to_string_parsers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('num to string parser tests', () {
    test(
        'fileAndFolderCountsToString returns the correct results '
        'for 1 file and 1 folder', () {
      expect(
        fileAndFolderCountsToString(folderCount: 1, fileCount: 1),
        equals('1 folder, 1 file'),
      );
    });
    test(
        'fileAndFolderCountsToString returns the correct results '
        'for 0 files and 0 folders', () {
      expect(
        fileAndFolderCountsToString(folderCount: 0, fileCount: 0),
        equals('0 folders, 0 files'),
      );
    });
    test(
        'fileAndFolderCountsToString returns the correct results '
        'for multiple files and multiple folders', () {
      //Generate random non zero counts
      final fileCount = Random().nextInt(9000) + 1;
      final folderCount = Random().nextInt(9000) + 1;
      expect(
        fileAndFolderCountsToString(
            folderCount: folderCount, fileCount: fileCount),
        equals('$folderCount folders, $fileCount files'),
      );
    });
  });
}

import 'package:ardrive/utils/num_to_string_parsers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('num to string parser tests', () {
    // The method is now using internationalization. Different ouputs are expected for different languages
    Skip;
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
        'for 0 files and 1 folder', () {
      expect(
        fileAndFolderCountsToString(folderCount: 1, fileCount: 0),
        equals('1 folder, 0 files'),
      );
    });
    test(
        'fileAndFolderCountsToString returns the correct results '
        'for 1 file and 0 folders', () {
      expect(
        fileAndFolderCountsToString(folderCount: 0, fileCount: 1),
        equals('0 folders, 1 file'),
      );
    });

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
        'for 2 files and 1 folder', () {
      expect(
        fileAndFolderCountsToString(folderCount: 1, fileCount: 2),
        equals('1 folder, 2 files'),
      );
    });

    test(
        'fileAndFolderCountsToString returns the correct results '
        'for 1 file and 2 folders', () {
      expect(
        fileAndFolderCountsToString(folderCount: 2, fileCount: 1),
        equals('2 folders, 1 file'),
      );
    });
    test(
        'fileAndFolderCountsToString returns the correct results '
        'for 2 files and 2 folders', () {
      expect(
        fileAndFolderCountsToString(folderCount: 2, fileCount: 2),
        equals('2 folders, 2 files'),
      );
    });
  });
}

import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/utils/has_arns_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// Mock classes
class MockFileDataTableItem extends Mock implements FileDataTableItem {}

class MockFolderDataTableItem extends Mock implements FolderDataTableItem {}

class MockDriveDataItem extends Mock implements DriveDataItem {}

void main() {
  group('hasArnsNames', () {
    late MockFileDataTableItem fileItem;
    late MockFolderDataTableItem folderItem;
    late MockDriveDataItem driveItem;

    setUp(() {
      fileItem = MockFileDataTableItem();
      folderItem = MockFolderDataTableItem();
      driveItem = MockDriveDataItem();
    });

    test(
        'returns false when item is not a FileDataTableItem (FolderDataTableItem)',
        () {
      expect(hasArnsNames(folderItem), isFalse);
    });

    test('returns false when item is not a FileDataTableItem (DriveDataItem)',
        () {
      expect(hasArnsNames(driveItem), isFalse);
    });

    test('returns false when assignedNames is null', () {
      when(() => fileItem.assignedNames).thenReturn(null);

      expect(hasArnsNames(fileItem), isFalse);
    });

    test('returns false when assignedNames is empty', () {
      when(() => fileItem.assignedNames).thenReturn([]);

      expect(hasArnsNames(fileItem), isFalse);
    });

    test('returns true when assignedNames has a single value', () {
      when(() => fileItem.assignedNames).thenReturn(['name1']);

      expect(hasArnsNames(fileItem), isTrue);
    });

    test('returns true when assignedNames has multiple values', () {
      when(() => fileItem.assignedNames)
          .thenReturn(['name1', 'name2', 'name3']);

      expect(hasArnsNames(fileItem), isTrue);
    });
  });
}

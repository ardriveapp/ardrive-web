import 'package:ardrive_io/src/io_exception.dart';
import 'package:ardrive_io/src/utils/file_path_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('test method getFolderNameFromPath', () {
    test('should return correct folder name', () {
      expect(getFolderNameFromPath('some-folder'), 'some-folder');
      expect(getFolderNameFromPath('/some-folder'), 'some-folder');
      expect(
          getFolderNameFromPath('some_directory/some-folder'), 'some-folder');
    });

    test('should throw an EntityPathException when got a empty path', () {
      expect(() => getFolderNameFromPath(''),
          throwsA(const TypeMatcher<EntityPathException>()));
    });
  });
}

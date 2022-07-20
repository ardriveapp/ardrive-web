import 'package:ardrive_io/src/io_exception.dart';
import 'package:ardrive_io/src/utils/file_path_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('test method getExtensionFromPath', () {
    test('should return correct extension', () {
      expect(getExtensionFromPath('file.txt'), 'txt');
      expect(getExtensionFromPath('file.jpg'), 'jpg');
      expect(getExtensionFromPath('some.file.jpg'), 'jpg');
      expect(getExtensionFromPath('some_directory/some.file.jpg'), 'jpg');
    });

    test('should throw an EntityPathException when got a empty path', () {
      expect(() => getExtensionFromPath(''),
          throwsA(const TypeMatcher<EntityPathException>()));
    });
  });
  group('test method getFolderNameFromPath', () {
    test('should return correct folder name', () {
      expect(getFolderNameFromPath('some-folder'), 'some-folder');
      expect(getExtensionFromPath('/some-folder'), 'some-folder');
      expect(getExtensionFromPath('some_directory/some-folder'), 'some-folder');
    });

    test('should throw an EntityPathException when got a empty path', () {
      expect(() => getExtensionFromPath(''),
          throwsA(const TypeMatcher<EntityPathException>()));
    });
  });
}

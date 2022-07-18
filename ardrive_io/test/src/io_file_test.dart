import 'dart:io';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_io/src/io_exception.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const String filePath = 'somefile.jpg';
  File file = File(filePath);

  late PlatformFile mockPlatformFile;
  late PlatformFile mockPlatformFileWithNullPath;

  IOFileAdapter sut = IOFileAdapter();

  setUp(() async {
    file.createSync();
    await file.writeAsBytes(ByteData(1024).buffer.asUint8List());

    mockPlatformFile = PlatformFile(
        name: 'name_from_file_picker',
        size: file.lengthSync(),
        path: file.path);

    mockPlatformFileWithNullPath =
        PlatformFile(name: 'name_from_file_picker', size: file.lengthSync());
  });

  tearDown(() {
    file.deleteSync();
  });

  group('test class IOFileAdapter method fromFilePicker', () {
    test('should return a correct IOFile', () async {
      final iofile = await sut.fromFilePicker(mockPlatformFile);

      expect(iofile.name, 'name_from_file_picker');
      expect(iofile.fileExtension, 'jpg');
      expect(iofile.path, filePath);
      expect(iofile.contentType, 'image/jpeg');

      /// It differs in some milisseconds, as we get the lastModifiedDate through
      /// the cross_file package
      expect(iofile.lastModifiedDate, await file.lastModified());

      /// ensure that is the same content
      expect(await iofile.readAsBytes(), await file.readAsBytes());
    });
    test('should throw an exception with a file without a path', () async {
      await expectLater(() => sut.fromFilePicker(mockPlatformFileWithNullPath),
          throwsA(const TypeMatcher<EntityPathException>()));
    });
  });

  group('test class IOFileAdapter method fromFile', () {
    test('should return a correct IOFile', () async {
      final iofile = await sut.fromFile(file);

      expect(iofile.name, filePath);
      expect(iofile.fileExtension, 'jpg');
      expect(iofile.path, filePath);
      expect(iofile.contentType, 'image/jpeg');

      expect(iofile.lastModifiedDate, await file.lastModified());

      /// ensure that is the same content
      expect(await iofile.readAsBytes(), await file.readAsBytes());
    });
  });
}

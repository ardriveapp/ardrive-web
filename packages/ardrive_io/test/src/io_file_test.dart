import 'dart:io';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:async/async.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
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
      expect(iofile.path, filePath);
      expect(iofile.contentType, 'image/jpeg');
      expect(iofile.length, file.lengthSync());

      /// It differs in some milisseconds, as we get the lastModifiedDate through
      /// the cross_file package
      expect(iofile.lastModifiedDate, await file.lastModified());

      /// ensure that is the same content
      expect(await iofile.readAsBytes(), await file.readAsBytes());
      expect(await collectBytes(iofile.openReadStream()), await file.readAsBytes());
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
      expect(iofile.path, filePath);
      expect(iofile.contentType, 'image/jpeg');
      expect(iofile.lastModifiedDate, await file.lastModified());
      expect(iofile.length, file.lengthSync());

      /// ensure that is the same content
      expect(await iofile.readAsBytes(), await file.readAsBytes());
      expect(await collectBytes(iofile.openReadStream()), await file.readAsBytes());
    });
  });
  group('test class IOFileAdapter method fromData', () {
    test('should return a correct IOFile', () async {
      final bytes = ByteData(1024).buffer.asUint8List();
      final dateCreated = DateTime.parse('2020-02-11');
      final iofile = await sut.fromData(bytes,
          lastModifiedDate: dateCreated, name: 'some_name.txt');

      expect(iofile.name, 'some_name.txt');
      expect(iofile.contentType, 'text/plain');
      expect(iofile.path, '');
      expect(dateCreated, iofile.lastModifiedDate);
      expect(iofile.length, bytes.length);

      /// ensure that is the same content
      expect(bytes, await iofile.readAsBytes());
      expect(bytes, await collectBytes(iofile.openReadStream()));
    });
  });

  group('test class IOFileAdapter fromWebXFile method ', () {
    test('should return a correct IOFile', () async {
      final iofile = await sut.fromWebXFile(
        XFile(file.path),
      );

      expect(iofile.name, 'somefile.jpg');
      expect(iofile.contentType, 'image/jpeg');
      expect(iofile.path, file.path);
      expect(await file.lastModified(), iofile.lastModifiedDate);
      expect(await iofile.length, await file.length());

      /// ensure that is the same content
      expect(await file.readAsBytes(), await iofile.readAsBytes());
      expect(await file.readAsBytes(), await collectBytes(iofile.openReadStream()));
    });
  });

  group('test class IOFile method fromData', () {
    test('should return a correct IOFile', () async {
      final bytes = ByteData(1024).buffer.asUint8List();
      final dateCreated = DateTime.parse('2020-02-11');
      final iofile = await IOFile.fromData(bytes,
          lastModifiedDate: dateCreated, name: 'some_name.txt');

      expect(iofile.name, 'some_name.txt');
      expect(iofile.contentType, 'text/plain');
      expect(iofile.path, '');
      expect(dateCreated, iofile.lastModifiedDate);
      expect(iofile.length, bytes.length);

      /// ensure that is the same content
      expect(bytes, await iofile.readAsBytes());
      expect(bytes, await collectBytes(iofile.openReadStream()));
    });
  });
}

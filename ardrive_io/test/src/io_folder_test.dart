import 'dart:io';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDirectory extends Mock implements Directory {}

class MockFile extends Mock implements File {}

void main() {
  final IOFolderAdapter sut;
  sut = IOFolderAdapter();

  /// We are testing if the following file system structure mounts correctly:
  /// first-level/
  ///     first-level-file.xpto
  ///     subdirectory-level/
  ///         subdirectory-file
  ///         subdirectory-file-1.xpto
  group('test class IOFolderAdapter', () {
    late Directory firstLevelDirectory = Directory('first-level');

    late Directory secondLevelDirectory =
        Directory('${firstLevelDirectory.path}/subdirectory-level');

    /// Create file system entities
    setUp(() {
      firstLevelDirectory.createSync();
      secondLevelDirectory.createSync();

      File('${firstLevelDirectory.path}/first-level-file.xpto').createSync();
      File('${secondLevelDirectory.path}/subdirectory-file').createSync();
      File('${secondLevelDirectory.path}/subdirectory-file-1.xpto')
          .createSync();
    });

    tearDown(() async {
      firstLevelDirectory.delete(
          recursive: true); // will delete all files and folders
    });

    test(
        'fromFileSystemDirectory method should return the folder hierachy correctly',
        () async {
      final firstLevelFolder =
          await sut.fromFileSystemDirectory(firstLevelDirectory);

      final firstLevelContent = await firstLevelFolder.listContent();

      expect(firstLevelFolder.name, 'first-level');
      expect(firstLevelFolder.path, 'first-level');
      expect(firstLevelFolder.lastModifiedDate,
          firstLevelDirectory.statSync().modified);

      /// First level folder content
      /// first-level/
      ///     first-level-file.xpto
      ///     subdirectory-level/
      expect(firstLevelContent.whereType<IOFolder>().length, 1);
      expect(firstLevelContent.whereType<IOFile>().length, 1);

      /// subdirectory-level/
      ///     subdirectory-file
      ///     subdirectory-file-1.xpto
      final secondLevelFolder = firstLevelContent.whereType<IOFolder>().first;
      expect(secondLevelFolder.name, 'subdirectory-level');
      expect(secondLevelFolder.path, secondLevelDirectory.path);
      expect(secondLevelFolder.lastModifiedDate,
          secondLevelDirectory.statSync().modified);

      /// get the second level and verify its content
      final secondLevelContent = await secondLevelFolder.listContent();
      expect(secondLevelContent.whereType<IOFile>().length, 2);
      expect(secondLevelContent.whereType<IOFolder>().length, 0);
    });
  });
}

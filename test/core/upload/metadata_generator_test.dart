import 'dart:typed_data';

import 'package:ardrive/core/upload/metadata_generator.dart';
import 'package:ardrive/core/upload/upload_metadata.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockARFSTagsGenetator extends Mock implements ARFSTagsGenetator {}

void main() {
  late ARFSUploadMetadataGenerator generator;
  late MockARFSTagsGenetator mockARFSTagsGenetator;

  final args = ARFSTagsArgs(
    driveId: 'driveId',
    parentFolderId: 'parentFolderId',
    privacy: 'public',
    entityId: 'entityId',
  );

  final metadataArgs = ARFSUploadMetadataArgs(
    driveId: 'driveId',
    parentFolderId: 'parentFolderId',
    privacy: 'public',
  );

  setUpAll(() {
    mockARFSTagsGenetator = MockARFSTagsGenetator();
    generator = ARFSUploadMetadataGenerator(
      tagsGenerator: mockARFSTagsGenetator,
    );

    registerFallbackValue(args);
  });

  group('generateMetadata', () {
    test('throws ArgumentError when arguments is null', () async {
      expect(
        () async => await generator.generateMetadata(
          await mockFile(),
          null,
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when generateTags throws', () async {
      when(() => mockARFSTagsGenetator.generateTags(any()))
          .thenThrow(Exception());

      expect(
        () async => await generator.generateMetadata(
          await mockFile(),
          metadataArgs,
        ),
        throwsException,
      );
    });

    test('throws when args is invalid for file', () async {
      expect(
        () async => await generator.generateMetadata(
          await mockFile(),
          ARFSUploadMetadataArgs(
            driveId: null,
            parentFolderId: null,
            privacy: null,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('returns ARFSFileUploadMetadata when entity is IOFile', () async {
      final file = await mockFile();

      when(() => mockARFSTagsGenetator.generateTags(any()))
          .thenReturn([Tag('tag', 'value')]);

      final metadata = await generator.generateMetadata(file, metadataArgs);

      expect(metadata, isA<ARFSFileUploadMetadata>());
      expect(metadata.tags[0].name, 'tag');
      expect(metadata.tags[0].value, 'value');
      expect(metadata.name, file.name);
      expect(metadata.id, isNotEmpty);
    });

    test('returns ARFSFolderUploadMetatadata when entity is IOFolder',
        () async {
      final folder = IOFolderAdapter().fromIOFiles([
        await mockFile(),
        await mockFile(),
      ]);

      when(() => mockARFSTagsGenetator.generateTags(any()))
          .thenReturn([Tag('entity', 'folder')]);

      final metadata = await generator.generateMetadata(folder, metadataArgs);

      expect(metadata, isA<ARFSFolderUploadMetatadata>());
      expect(metadata.tags[0].name, 'entity');
      expect(metadata.tags[0].value, 'folder');
      expect(metadata.name, folder.name);
      expect(metadata.id, isNotEmpty);
    });

    test('returns ARFSDriveUploadMetadata when we call the generateDrive',
        () async {
      when(() => mockARFSTagsGenetator.generateTags(any()))
          .thenReturn([Tag('entity', 'drive')]);

      final drive = await generator.generateDrive(
        name: 'name',
        privacy: 'public',
      );

      expect(drive, isA<ARFSDriveUploadMetadata>());
      expect(drive.tags[0].name, 'entity');
      expect(drive.tags[0].value, 'drive');
      expect(drive.name, 'name');
      expect(drive.id, isNotEmpty);
    });
  });

  // TODO: implement tests for validation of args
}

Future<IOFile> mockFile() {
  return IOFileAdapter().fromData(
    Uint8List(10),
    name: 'test.txt',
    lastModifiedDate: DateTime.now(),
    contentType: 'text/plain',
  );
}

import 'dart:typed_data';

import 'package:ardrive/core/arfs/entities/arfs_entities.dart' as arfs;
import 'package:ardrive/core/upload/metadata_generator.dart';
import 'package:ardrive/core/upload/upload_metadata.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/services/app/app_info_services.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockARFSTagsGenetator extends Mock implements ARFSTagsGenetator {}

class MockAppInfoServices extends Mock implements AppInfoServices {}

void main() {
  late ARFSUploadMetadataGenerator generator;
  late MockARFSTagsGenetator mockARFSTagsGenetator;

  final args = ARFSTagsArgs(
    driveId: 'driveId',
    parentFolderId: 'parentFolderId',
    isPrivate: false,
    entityId: 'entityId',
  );

  final metadataArgsPublic = ARFSUploadMetadataArgs(
    driveId: 'driveId',
    parentFolderId: 'parentFolderId',
    privacy: 'public',
    isPrivate: false,
  );

  final metadataArgsPrivate = ARFSUploadMetadataArgs(
    driveId: 'driveId',
    parentFolderId: 'parentFolderId',
    privacy: 'private',
    isPrivate: true,
  );

  setUpAll(() {
    mockARFSTagsGenetator = MockARFSTagsGenetator();
    generator = ARFSUploadMetadataGenerator(
      tagsGenerator: mockARFSTagsGenetator,
    );

    registerFallbackValue(args);
  });

  group('ARFSUploadMetadataGenetator', () {
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

      test('throws ArgumentError when generateTags throws generating a file',
          () async {
        when(() => mockARFSTagsGenetator.generateTags(any()))
            .thenThrow(Exception());

        expect(
          () async => await generator.generateMetadata(
            await mockFile(),
            metadataArgsPublic,
          ),
          throwsException,
        );
      });

      test('throws ArgumentError when generateTags throws generating a folder',
          () async {
        final folder = IOFolderAdapter().fromIOFiles([
          await mockFile(),
          await mockFile(),
        ]);

        when(() => mockARFSTagsGenetator.generateTags(any()))
            .thenThrow(Exception());

        expect(
          () async => await generator.generateMetadata(
            folder,
            metadataArgsPublic,
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
              isPrivate: false,
            ),
          ),
          throwsArgumentError,
        );
      });

      test('returns ARFSFileUploadMetadata when entity is IOFile', () async {
        final file = await mockFile();

        when(() => mockARFSTagsGenetator.generateTags(any()))
            .thenReturn([Tag('tag', 'value')]);

        final metadataPublic =
            await generator.generateMetadata(file, metadataArgsPublic);
        final metadataPrivate =
            await generator.generateMetadata(file, metadataArgsPrivate);

        expect(metadataPublic, isA<ARFSFileUploadMetadata>());
        expect(metadataPublic.tags[0].name, 'tag');
        expect(metadataPublic.tags[0].value, 'value');
        expect(metadataPublic.name, file.name);
        expect(metadataPublic.id, isNotEmpty);
        expect(metadataPublic.isPrivate, false);

        expect(metadataPrivate, isA<ARFSFileUploadMetadata>());
        expect(metadataPrivate.tags[0].name, 'tag');
        expect(metadataPrivate.tags[0].value, 'value');
        expect(metadataPrivate.name, file.name);
        expect(metadataPrivate.id, isNotEmpty);
        expect(metadataPrivate.isPrivate, true);
      });

      test('returns ARFSFolderUploadMetatadata when entity is IOFolder',
          () async {
        final folder = IOFolderAdapter().fromIOFiles([
          await mockFile(),
          await mockFile(),
        ]);

        when(() => mockARFSTagsGenetator.generateTags(any()))
            .thenReturn([Tag('entity', 'folder')]);

        final metadataPublic =
            await generator.generateMetadata(folder, metadataArgsPublic);
        final metadataPrivate =
            await generator.generateMetadata(folder, metadataArgsPrivate);

        expect(metadataPublic, isA<ARFSFolderUploadMetatadata>());
        expect(metadataPublic.tags[0].name, 'entity');
        expect(metadataPublic.tags[0].value, 'folder');
        expect(metadataPublic.name, folder.name);
        expect(metadataPublic.id, isNotEmpty);
        expect(metadataPublic.isPrivate, false);

        expect(metadataPrivate, isA<ARFSFolderUploadMetatadata>());
        expect(metadataPrivate.tags[0].name, 'entity');
        expect(metadataPrivate.tags[0].value, 'folder');
        expect(metadataPrivate.name, folder.name);
        expect(metadataPrivate.id, isNotEmpty);
        expect(metadataPrivate.isPrivate, true);
      });
    });
    group('generateDrive', () {
      test('returns ARFSDriveUploadMetadata when we call the generateDrive',
          () async {
        when(() => mockARFSTagsGenetator.generateTags(any()))
            .thenReturn([Tag('entity', 'drive')]);

        final drivePublic = await generator.generateDrive(
          name: 'name',
          isPrivate: false,
        );

        final drivePrivate = await generator.generateDrive(
          name: 'name',
          isPrivate: true,
        );

        expect(drivePublic, isA<ARFSDriveUploadMetadata>());
        expect(drivePublic.tags[0].name, 'entity');
        expect(drivePublic.tags[0].value, 'drive');
        expect(drivePublic.name, 'name');
        expect(drivePublic.id, isNotEmpty);
        expect(drivePublic.isPrivate, false);

        expect(drivePrivate, isA<ARFSDriveUploadMetadata>());
        expect(drivePrivate.tags[0].name, 'entity');
        expect(drivePrivate.tags[0].value, 'drive');
        expect(drivePrivate.name, 'name');
        expect(drivePrivate.id, isNotEmpty);
        expect(drivePrivate.isPrivate, true);
      });
    });
  });

  group('ARFSTagsGenerator', () {
    final appInfoServices = MockAppInfoServices();

    group('generateTags', () {
      test('should generate the proper tags for a entity file', () {
        final ARFSTagsGenetator tagsGenerator = ARFSTagsGenetator(
            appInfoServices: appInfoServices, entity: arfs.EntityType.file);

        when(() => appInfoServices.appInfo).thenReturn(
          AppInfo(
            arfsVersion: '1',
            version: 'version',
            appName: 'ArDrive',
            platform: 'platform',
          ),
        );

        final tags = tagsGenerator.generateTags(args);

        // app tags
        tags.contains(Tag(EntityTag.arFs, '1'));
        tags.contains(Tag(EntityTag.appVersion, 'version'));
        tags.contains(Tag(EntityTag.appPlatform, 'platform'));
        tags.contains(Tag(EntityTag.appName, 'Ardrive'));

        // entity tags
        tags.contains(Tag(EntityTag.fileId, 'entityId'));
        tags.contains(Tag(EntityTag.parentFolderId, 'parentFolderId'));
        tags.contains(Tag(EntityTag.driveId, 'driveId'));
        tags.contains(Tag(EntityTag.entityType, arfs.EntityType.file.name));

        // u tags
        tags.contains(Tag(EntityTag.appName, 'SmartWeaveAction'));
        tags.contains(Tag(EntityTag.appVersion, '0.3.0'));
        tags.contains(Tag(EntityTag.input, '{"function":"mint"}'));
        tags.contains(Tag(
            EntityTag.contract, 'KTzTXT_ANmF84fWEKHzWURD1LWd9QaFR9yfYUwH2Lxw'));

        expect(
          tags
              .firstWhere((element) => element.name == EntityTag.unixTime)
              .value,
          isNotNull,
        );
        expect(tags.length, 12);
      });

      test('should generate the proper tags for a entity folder', () {
        final ARFSTagsGenetator tagsGenerator = ARFSTagsGenetator(
            appInfoServices: appInfoServices, entity: arfs.EntityType.folder);

        when(() => appInfoServices.appInfo).thenReturn(
          AppInfo(
            arfsVersion: '1',
            version: 'version',
            appName: 'ArDrive',
            platform: 'platform',
          ),
        );
        final tags = tagsGenerator.generateTags(args);

        // app tags
        tags.contains(Tag(EntityTag.arFs, '1'));
        tags.contains(Tag(EntityTag.appVersion, 'version'));
        tags.contains(Tag(EntityTag.appPlatform, 'platform'));
        tags.contains(Tag(EntityTag.appName, 'Ardrive'));

        // entity tags
        tags.contains(Tag(EntityTag.folderId, 'entityId'));
        tags.contains(Tag(EntityTag.parentFolderId, 'parentFolderId'));
        tags.contains(Tag(EntityTag.driveId, 'driveId'));
        tags.contains(Tag(EntityTag.entityType, arfs.EntityType.folder.name));

        // u tags
        tags.contains(Tag(EntityTag.appName, 'SmartWeaveAction'));
        tags.contains(Tag(EntityTag.appVersion, '0.3.0'));
        tags.contains(Tag(EntityTag.input, '{"function":"mint"}'));
        tags.contains(Tag(
            EntityTag.contract, 'KTzTXT_ANmF84fWEKHzWURD1LWd9QaFR9yfYUwH2Lxw'));

        expect(
          tags
              .firstWhere((element) => element.name == EntityTag.unixTime)
              .value,
          isNotNull,
        );
        expect(tags.length, 12);
      });
      test('should generate the proper tags for a entity drive', () {
        final ARFSTagsGenetator tagsGenerator = ARFSTagsGenetator(
            appInfoServices: appInfoServices, entity: arfs.EntityType.drive);

        when(() => appInfoServices.appInfo).thenReturn(
          AppInfo(
            arfsVersion: '1',
            version: 'version',
            appName: 'ArDrive',
            platform: 'platform',
          ),
        );
        final tags = tagsGenerator.generateTags(args);

        // app tags
        tags.contains(Tag(EntityTag.arFs, '1'));
        tags.contains(Tag(EntityTag.appVersion, 'version'));
        tags.contains(Tag(EntityTag.appPlatform, 'platform'));
        tags.contains(Tag(EntityTag.appName, 'Ardrive'));

        // entity tags
        tags.contains(Tag(EntityTag.driveId, 'driveId'));
        tags.contains(Tag(EntityTag.entityType, arfs.EntityType.drive.name));

        // u tags
        tags.contains(Tag(EntityTag.appName, 'SmartWeaveAction'));
        tags.contains(Tag(EntityTag.appVersion, '0.3.0'));
        tags.contains(Tag(EntityTag.input, '{"function":"mint"}'));
        tags.contains(Tag(
            EntityTag.contract, 'KTzTXT_ANmF84fWEKHzWURD1LWd9QaFR9yfYUwH2Lxw'));

        expect(
          tags
              .firstWhere((element) => element.name == EntityTag.unixTime)
              .value,
          isNotNull,
        );
        expect(tags.length, 10);
      });

      test('should throw if the args is invalid generating a drive', () {
        final ARFSTagsGenetator tagsGenerator = ARFSTagsGenetator(
            appInfoServices: appInfoServices, entity: arfs.EntityType.drive);

        when(() => appInfoServices.appInfo).thenReturn(
          AppInfo(
            arfsVersion: '1',
            version: 'version',
            appName: 'ArDrive',
            platform: 'platform',
          ),
        );

        final wrongArgs = ARFSTagsArgs(
          driveId: null,
          isPrivate: null,
        );

        expect(
            () => tagsGenerator.generateTags(wrongArgs), throwsArgumentError);
      });
      test('should throw if the args is invalid generating a file', () {
        final ARFSTagsGenetator tagsGenerator = ARFSTagsGenetator(
            appInfoServices: appInfoServices, entity: arfs.EntityType.file);

        when(() => appInfoServices.appInfo).thenReturn(
          AppInfo(
            arfsVersion: '1',
            version: 'version',
            appName: 'ArDrive',
            platform: 'platform',
          ),
        );

        final wrongArgs = ARFSTagsArgs(
          driveId: null,
          parentFolderId: null,
        );

        expect(
            () => tagsGenerator.generateTags(wrongArgs), throwsArgumentError);
      });

      test('should throw if the args is invalid generating a folder', () {
        final ARFSTagsGenetator tagsGenerator = ARFSTagsGenetator(
            appInfoServices: appInfoServices, entity: arfs.EntityType.file);

        when(() => appInfoServices.appInfo).thenReturn(
          AppInfo(
            arfsVersion: '1',
            version: 'version',
            appName: 'ArDrive',
            platform: 'platform',
          ),
        );

        final wrongArgs = ARFSTagsArgs(
          driveId: null,
          parentFolderId: null,
        );

        expect(
            () => tagsGenerator.generateTags(wrongArgs), throwsArgumentError);
      });
    });
  });

  group('ARFSTagsValidator', () {
    group('validate', () {
      test('should not throw if the args is valid generating a drive', () {
        final wrongArgs = ARFSTagsArgs(
          driveId: 'drive id',
          isPrivate: false,
        );

        expect(
            () => ARFSTagsValidator.validate(wrongArgs, arfs.EntityType.drive),
            returnsNormally);
      });
      test('should throw if the args is invalid generating a drive', () {
        final wrongArgs = ARFSTagsArgs(
          driveId: null,
          isPrivate: null,
        );

        expect(
            () => ARFSTagsValidator.validate(wrongArgs, arfs.EntityType.drive),
            throwsArgumentError);
      });
      test('should not throw if the args is valid generating a file', () {
        final wrongArgs = ARFSTagsArgs(
          driveId: 'drive id',
          parentFolderId: 'parent folder id',
          entityId: 'entity id',
        );

        expect(
            () => ARFSTagsValidator.validate(wrongArgs, arfs.EntityType.file),
            returnsNormally);
      });
      test('should throw if the args is invalid generating a file', () {
        final wrongArgs = ARFSTagsArgs(
          driveId: null,
        );

        expect(
            () => ARFSTagsValidator.validate(wrongArgs, arfs.EntityType.file),
            throwsArgumentError);

        final wrongArgs2 = ARFSTagsArgs(
          driveId: 'not null',
          parentFolderId: null,
        );

        expect(
            () => ARFSTagsValidator.validate(wrongArgs2, arfs.EntityType.file),
            throwsArgumentError);

        final wrongArgs3 = ARFSTagsArgs(
          driveId: 'not null',
          parentFolderId: 'not null',
          entityId: null,
        );

        expect(
            () => ARFSTagsValidator.validate(wrongArgs3, arfs.EntityType.file),
            throwsArgumentError);
      });

      test('should not throw if the args is valid generating a folder', () {
        final wrongArgs = ARFSTagsArgs(
          driveId: 'drive id',
          isPrivate: false,
          entityId: 'entity id',
        );

        expect(
            () => ARFSTagsValidator.validate(wrongArgs, arfs.EntityType.folder),
            returnsNormally);
      });

      test('should throw if the args is invalid generating a folder', () {
        final wrongArgs = ARFSTagsArgs(
          driveId: null,
        );

        expect(
            () => ARFSTagsValidator.validate(wrongArgs, arfs.EntityType.folder),
            throwsArgumentError);

        final wrongArgs2 = ARFSTagsArgs(
          driveId: 'not null',
          entityId: null,
        );
        expect(
            () =>
                ARFSTagsValidator.validate(wrongArgs2, arfs.EntityType.folder),
            throwsArgumentError);
      });
    });
  });
}

Future<IOFile> mockFile() {
  return IOFileAdapter().fromData(
    Uint8List(10),
    name: 'test.txt',
    lastModifiedDate: DateTime.now(),
    contentType: 'text/plain',
  );
}

import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arfs/arfs.dart';
import 'package:arweave/arweave.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAppInfoServices extends Mock implements AppInfoServices {}

class MockARFSTagsGenetator extends Mock implements ARFSTagsGenetator {}

void main() {
  late MockAppInfoServices mockAppInfoServices;
  late MockARFSTagsGenetator mockARFSTagsGenetator;
  late ARFSTagsGenetator tagsGenerator;
  late ARFSUploadMetadataGenerator metadataGenerator;
  late AppInfo appInfo; // Assuming AppInfo is a class you have defined

  setUpAll(() {
    registerFallbackValue(ARFSTagsArgs(
      isPrivate: false,
      contentType: 'text/plain',
      entity: EntityType.file,
      entityId: 'entity123',
      driveId: 'driveId',
      parentFolderId: 'parentFolderId',
    ));
  });

  setUp(() {
    mockAppInfoServices = MockAppInfoServices();
    tagsGenerator = ARFSTagsGenetator(appInfoServices: mockAppInfoServices);
    mockARFSTagsGenetator = MockARFSTagsGenetator();
    metadataGenerator = ARFSUploadMetadataGenerator(
      tagsGenerator: mockARFSTagsGenetator,
    );

    // Mock AppInfo
    appInfo = AppInfo(
      version: '2.22.0',
      platform: 'FlutterTest',
      arfsVersion: '0.14',
      appName: 'ardrive',
    );

    // Mocking the appInfoServices response
    when(() => mockAppInfoServices.appInfo).thenReturn(appInfo);
  });

  group('ARFSUploadMetadataGenerator', () {
    group('generateMetadata for IOFile', () {
      test('throws if arguments is null', () {
        expect(() => metadataGenerator.generateMetadata(DumbIOFile()),
            throwsA(isA<ArgumentError>()));
      });

      test('throws if entity type is null', () {
        expect(
            () => metadataGenerator.generateMetadata(
                DumbIOFile(),
                ARFSUploadMetadataArgs(
                  isPrivate: false,
                  type: UploadType.d2n,
                  entityId: null,
                )),
            throwsA(isA<ArgumentError>()));
      });

      test('throws if drive id is null', () {
        expect(
            () => metadataGenerator.generateMetadata(
                DumbIOFile(),
                ARFSUploadMetadataArgs(
                  isPrivate: false,
                  type: UploadType.d2n,
                  entityId: 'entity123',
                  driveId: null,
                )),
            throwsA(isA<ArgumentError>()));
      });

      test('throws if parentFolderId is null', () {
        expect(
            () => metadataGenerator.generateMetadata(
                DumbIOFile(),
                ARFSUploadMetadataArgs(
                  isPrivate: false,
                  type: UploadType.d2n,
                  entityId: 'entity123',
                  driveId: 'driveId',
                  parentFolderId: null,
                )),
            throwsA(isA<ArgumentError>()));
      });
      test('generates metadata for standard public file input for D2N',
          () async {
        final argsForD2NWithUTags = ARFSTagsArgs(
          isPrivate: false,
          contentType: 'text/plain',
          entity: EntityType.file,
          customBundleTags: [
            Tag(EntityTag.appName, 'SmartWeaveAction'),
            Tag(EntityTag.appVersion, '0.3.0'),
            Tag(EntityTag.input, '{"function":"mint"}'),
            Tag(EntityTag.contract,
                'KTzTXT_ANmF84fWEKHzWURD1LWd9QaFR9yfYUwH2Lxw'),
          ],
          entityId: 'entity123',
          driveId: 'driveId',
          parentFolderId: 'parentFolderId',
        );

        when(() => mockARFSTagsGenetator.generateTags(argsForD2NWithUTags))
            .thenReturn({
          'data-item': [
            Tag('data-item-tag-name', 'data-item-tag-value'),
          ],
          'bundle-data-item': [
            Tag('bundle-data-item-tag-name', 'bundle-data-item-tag-value'),
          ],
          'entity': [
            Tag('entity-tag-name', 'entity-tag-value'),
          ],
        });

        final metadata = await metadataGenerator.generateMetadata(
          DumbIOFile(),
          ARFSUploadMetadataArgs(
            isPrivate: false,
            type: UploadType.d2n,
            entityId: 'entity123',
            driveId: 'driveId',
            parentFolderId: 'parentFolderId',
          ),
        );

        /// validate tags
        expect(metadata.bundleTags, [
          Tag('bundle-data-item-tag-name', 'bundle-data-item-tag-value'),
        ]);
        expect(metadata.dataItemTags, [
          Tag('data-item-tag-name', 'data-item-tag-value'),
        ]);
        expect(metadata.entityMetadataTags, [
          Tag('entity-tag-name', 'entity-tag-value'),
        ]);

        /// validate metadata
        expect(metadata.name, 'name');
        expect(metadata.id, isNotNull);
        expect(metadata.isPrivate, false);

        /// validate metadataTxId
        metadata.setMetadataTxId = 'metadataTxId';

        expect(metadata.metadataTxId, 'metadataTxId');

        /// We are verifying if the $U tags are being passed when using the
        /// ARFSTagsGenetator uploading to D2N
        verify(() => mockARFSTagsGenetator.generateTags(argsForD2NWithUTags));
      });

      test('generates metadata for standard private file input for D2N',
          () async {
        final argsForD2NWithUTagsPrivate = ARFSTagsArgs(
          isPrivate: true,
          contentType: 'application/octet-stream',
          entity: EntityType.file,
          customBundleTags: [
            Tag(EntityTag.appName, 'SmartWeaveAction'),
            Tag(EntityTag.appVersion, '0.3.0'),
            Tag(EntityTag.input, '{"function":"mint"}'),
            Tag(EntityTag.contract,
                'KTzTXT_ANmF84fWEKHzWURD1LWd9QaFR9yfYUwH2Lxw'),
          ],
          entityId: 'entity123',
          driveId: 'driveId',
          parentFolderId: 'parentFolderId',
        );

        when(() => mockARFSTagsGenetator.generateTags(any())).thenReturn({
          'data-item': [
            Tag('data-item-tag-name', 'data-item-tag-value'),
          ],
          'bundle-data-item': [
            Tag('bundle-data-item-tag-name', 'bundle-data-item-tag-value'),
          ],
          'entity': [
            Tag('entity-tag-name', 'entity-tag-value'),
          ],
        });

        final metadata = await metadataGenerator.generateMetadata(
          DumbIOFile(),
          ARFSUploadMetadataArgs(
            isPrivate: true, // private file
            type: UploadType.d2n,
            entityId: 'entity123',
            driveId: 'driveId',
            parentFolderId: 'parentFolderId',
          ),
        );

        /// validate tags
        expect(metadata.bundleTags, [
          Tag('bundle-data-item-tag-name', 'bundle-data-item-tag-value'),
        ]);
        expect(metadata.dataItemTags, [
          Tag('data-item-tag-name', 'data-item-tag-value'),
        ]);
        expect(metadata.entityMetadataTags, [
          Tag('entity-tag-name', 'entity-tag-value'),
        ]);

        /// validate metadata
        expect(metadata.name, 'name');
        expect(metadata.id, isNotNull);
        expect(metadata.isPrivate, true);

        /// validate metadataTxId
        metadata.setMetadataTxId = 'metadataTxId';

        expect(metadata.metadataTxId, 'metadataTxId');

        /// We are verifying if the $U tags are being passed when using the
        /// ARFSTagsGenetator uploading to D2N
        verify(() =>
            mockARFSTagsGenetator.generateTags(argsForD2NWithUTagsPrivate));
      });

      test('generates metadata for standard public file input for Turbo',
          () async {
        final argsForTurboPublic = ARFSTagsArgs(
          isPrivate: false,
          contentType: 'text/plain',
          entity: EntityType.file,
          entityId: 'entity123',
          driveId: 'driveId',
          parentFolderId: 'parentFolderId',
        );

        when(() => mockARFSTagsGenetator.generateTags(any())).thenReturn({
          'data-item': [
            Tag('data-item-tag-name', 'data-item-tag-value'),
          ],
          'bundle-data-item': [
            Tag('bundle-data-item-tag-name', 'bundle-data-item-tag-value'),
          ],
          'entity': [
            Tag('entity-tag-name', 'entity-tag-value'),
          ],
        });

        final metadata = await metadataGenerator.generateMetadata(
          DumbIOFile(),
          ARFSUploadMetadataArgs(
            isPrivate: false,
            type: UploadType.turbo,
            entityId: 'entity123',
            driveId: 'driveId',
            parentFolderId: 'parentFolderId',
          ),
        );

        /// validate tags
        expect(metadata.bundleTags, [
          Tag('bundle-data-item-tag-name', 'bundle-data-item-tag-value'),
        ]);
        expect(metadata.dataItemTags, [
          Tag('data-item-tag-name', 'data-item-tag-value'),
        ]);
        expect(metadata.entityMetadataTags, [
          Tag('entity-tag-name', 'entity-tag-value'),
        ]);

        /// validate metadata
        expect(metadata.name, 'name');
        expect(metadata.id, isNotNull);
        expect(metadata.isPrivate, false);

        /// validate metadataTxId
        metadata.setMetadataTxId = 'metadataTxId';

        expect(metadata.metadataTxId, 'metadataTxId');

        verify(() => mockARFSTagsGenetator.generateTags(argsForTurboPublic));
      });
      test('generates metadata for standard private file input for Turbo',
          () async {
        final argsForTurboPrivate = ARFSTagsArgs(
          isPrivate: true,
          contentType: 'application/octet-stream',
          entity: EntityType.file,
          entityId: 'entity123',
          driveId: 'driveId',
          parentFolderId: 'parentFolderId',
        );

        when(() => mockARFSTagsGenetator.generateTags(any())).thenReturn({
          'data-item': [
            Tag('data-item-tag-name', 'data-item-tag-value'),
          ],
          'bundle-data-item': [
            Tag('bundle-data-item-tag-name', 'bundle-data-item-tag-value'),
          ],
          'entity': [
            Tag('entity-tag-name', 'entity-tag-value'),
          ],
        });

        final metadata = await metadataGenerator.generateMetadata(
          DumbIOFile(),
          ARFSUploadMetadataArgs(
            isPrivate: true, // private file
            type: UploadType.turbo,
            entityId: 'entity123',
            driveId: 'driveId',
            parentFolderId: 'parentFolderId',
          ),
        );

        /// validate tags
        expect(metadata.bundleTags, [
          Tag('bundle-data-item-tag-name', 'bundle-data-item-tag-value'),
        ]);
        expect(metadata.dataItemTags, [
          Tag('data-item-tag-name', 'data-item-tag-value'),
        ]);
        expect(metadata.entityMetadataTags, [
          Tag('entity-tag-name', 'entity-tag-value'),
        ]);

        /// validate metadata
        expect(metadata.name, 'name');
        expect(metadata.id, isNotNull);
        expect(metadata.isPrivate, true);

        /// validate metadataTxId
        metadata.setMetadataTxId = 'metadataTxId';

        expect(metadata.metadataTxId, 'metadataTxId');

        verify(() => mockARFSTagsGenetator.generateTags(argsForTurboPrivate));
      });
    });
  });

  group('ARFSTagsGenetator', () {
    test('Throws if driveId is null when creating a file', () {
      // Define standard ARFSTagsArgs
      var args = ARFSTagsArgs(
        driveId: null,
        entityId: 'entity123',
        contentType: 'text/plain',
        entity: EntityType.file,
        isPrivate: false,
      );

      // Call generateTags
      expect(() => tagsGenerator.generateTags(args),
          throwsA(isA<ArgumentError>()));
    });

    test('Throws if parentFolderId is null when creating a file', () {
      // Define standard ARFSTagsArgs
      var args = ARFSTagsArgs(
        driveId: 'driveId',
        parentFolderId: null,
        entityId: 'entity123',
        contentType: 'text/plain',
        entity: EntityType.file,
        isPrivate: false,
      );

      // Call generateTags
      expect(() => tagsGenerator.generateTags(args),
          throwsA(isA<ArgumentError>()));
    });

    test('Throws if entityId is null when creating a file', () {
      // Define standard ARFSTagsArgs
      var args = ARFSTagsArgs(
        driveId: 'driveId',
        parentFolderId: 'parentFolderId',
        entityId: null,
        contentType: 'text/plain',
        entity: EntityType.file,
        isPrivate: false,
      );

      // Call generateTags
      expect(() => tagsGenerator.generateTags(args),
          throwsA(isA<ArgumentError>()));
    });

    test('Throws if entityId is null when creating a folder', () {
      // Define standard ARFSTagsArgs
      var args = ARFSTagsArgs(
        driveId: 'driveId',
        parentFolderId: 'parentFolderId',
        entityId: null,
        contentType: 'text/plain',
        entity: EntityType.folder,
        isPrivate: false,
      );

      // Call generateTags
      expect(() => tagsGenerator.generateTags(args),
          throwsA(isA<ArgumentError>()));
    });

    test('Throws if driveId is null when creating a folder', () {
      // Define standard ARFSTagsArgs
      var args = ARFSTagsArgs(
        driveId: null,
        entityId: 'entity123',
        contentType: 'text/plain',
        entity: EntityType.folder,
        isPrivate: false,
      );

      // Call generateTags
      expect(() => tagsGenerator.generateTags(args),
          throwsA(isA<ArgumentError>()));
    });

    test('Throws if driveId is null when creating a drive', () {
      // Define standard ARFSTagsArgs
      var args = ARFSTagsArgs(
        driveId: null,
        entityId: 'entity123',
        contentType: 'text/plain',
        entity: EntityType.drive,
        isPrivate: false,
      );

      // Call generateTags
      expect(() => tagsGenerator.generateTags(args),
          throwsA(isA<ArgumentError>()));
    });

    group('generating tags for files', () {
      test('Generates tags for standard public file input', () {
        // Define standard ARFSTagsArgs
        var args = ARFSTagsArgs(
          driveId: 'drive123',
          entityId: 'entity123',
          contentType: 'text/plain',
          entity: EntityType.file,
          isPrivate: false,
          parentFolderId: 'parentFolder123',
        );

        var result = tagsGenerator.generateTags(args);

        final dataItemTags = result['data-item'];
        final bundleTags = result['bundle-data-item'];
        final entityTags = result['entity'];

        final dataItemTagsMap = <String, dynamic>{};
        final bundleDataItemTagsMap = <String, dynamic>{};
        final entityDataItemTagsMap = <String, dynamic>{};

        for (var tag in dataItemTags!) {
          dataItemTagsMap[tag.name] = tag.value;
        }

        for (var tag in bundleTags!) {
          bundleDataItemTagsMap[tag.name] = tag.value;
        }

        for (var tag in entityTags!) {
          entityDataItemTagsMap[tag.name] = tag.value;
        }

        // Assert

        // dataItemTags
        expect(dataItemTagsMap[EntityTag.contentType], 'text/plain');
        _validateAppTags(dataItemTagsMap, appInfo);

        // bundleTags
        expect(bundleDataItemTagsMap[EntityTag.tipType], 'data upload');
        _validateAppTags(bundleDataItemTagsMap, appInfo);

        // entity
        expect(entityDataItemTagsMap[EntityTag.driveId], 'drive123');
        expect(
            entityDataItemTagsMap[EntityTag.contentType], 'application/json');
        expect(entityDataItemTagsMap[EntityTag.fileId], 'entity123');
        expect(
            entityDataItemTagsMap[EntityTag.parentFolderId], 'parentFolder123');
        expect(entityDataItemTagsMap[EntityTag.entityType], EntityTypeTag.file);
        _validateAppTags(entityDataItemTagsMap, appInfo);
      });

      test('Generates tags for standard private file input', () {
        // Define standard ARFSTagsArgs
        var args = ARFSTagsArgs(
          driveId: 'drive123',
          entityId: 'entity123',
          contentType: 'text/plain',
          entity: EntityType.file,
          isPrivate: true, // private file
          parentFolderId: 'parentFolder123',
        );

        var result = tagsGenerator.generateTags(args);

        final dataItemTags = result['data-item'];
        final bundleTags = result['bundle-data-item'];
        final entityTags = result['entity'];

        final dataItemTagsMap = <String, dynamic>{};
        final bundleDataItemTagsMap = <String, dynamic>{};
        final entityDataItemTagsMap = <String, dynamic>{};

        for (var tag in dataItemTags!) {
          dataItemTagsMap[tag.name] = tag.value;
        }

        for (var tag in bundleTags!) {
          bundleDataItemTagsMap[tag.name] = tag.value;
        }

        for (var tag in entityTags!) {
          entityDataItemTagsMap[tag.name] = tag.value;
        }

        // Assert

        // dataItemTags
        expect(dataItemTagsMap[EntityTag.contentType], 'text/plain');
        _validateAppTags(dataItemTagsMap, appInfo);

        // bundleTags
        expect(bundleDataItemTagsMap['Tip-Type'], 'data upload');
        _validateAppTags(bundleDataItemTagsMap, appInfo);

        // entity
        expect(entityDataItemTagsMap[EntityTag.driveId], 'drive123');

        /// For private files the content type is application/octet-stream
        expect(entityDataItemTagsMap[EntityTag.contentType],
            'application/octet-stream');
        expect(entityDataItemTagsMap[EntityTag.fileId], 'entity123');
        expect(
            entityDataItemTagsMap[EntityTag.parentFolderId], 'parentFolder123');
        expect(entityDataItemTagsMap[EntityTag.entityType], EntityTypeTag.file);

        _validateAppTags(entityDataItemTagsMap, appInfo);
      });

      test(
          'Generates tags for standard public file input with CUSTOM bundle tags',
          () {
        var args = ARFSTagsArgs(
          driveId: 'drive123',
          entityId: 'entity123',
          contentType: 'text/plain',
          entity: EntityType.file,
          isPrivate: false,
          parentFolderId: 'parentFolder123',
          customBundleTags: [
            Tag('custom-tag-name', 'custom-tag-value'),
          ],
        );

        var result = tagsGenerator.generateTags(args);

        final bundleTags = result['bundle-data-item'];

        final bundleDataItemTagsMap = <String, dynamic>{};

        for (var tag in bundleTags!) {
          bundleDataItemTagsMap[tag.name] = tag.value;
        }

        expect(bundleDataItemTagsMap['custom-tag-name'], 'custom-tag-value');
      });
    });

    group('generating tags for folders', () {
      test('Generates tags for standard a public folder input', () {
        // Define standard ARFSTagsArgs
        var args = ARFSTagsArgs(
          driveId: 'drive123',
          entityId: 'entity123',
          contentType: 'application/json',
          entity: EntityType.folder,
          isPrivate: false,
          parentFolderId: 'parentFolder123',
        );

        var result = tagsGenerator.generateTags(args);

        final dataItemTags = result['data-item'];
        final bundleTags = result['bundle-data-item'];
        final entityTags = result['entity'];

        final dataItemTagsMap = <String, dynamic>{};
        final bundleDataItemTagsMap = <String, dynamic>{};
        final entityDataItemTagsMap = <String, dynamic>{};

        for (var tag in dataItemTags!) {
          dataItemTagsMap[tag.name] = tag.value;
        }

        for (var tag in bundleTags!) {
          bundleDataItemTagsMap[tag.name] = tag.value;
        }

        for (var tag in entityTags!) {
          entityDataItemTagsMap[tag.name] = tag.value;
        }

        // Assert

        // dataItemTags
        expect(dataItemTagsMap[EntityTag.contentType], 'application/json');
        _validateAppTags(dataItemTagsMap, appInfo);

        // bundleTags
        expect(bundleDataItemTagsMap['Tip-Type'], 'data upload');
        _validateAppTags(bundleDataItemTagsMap, appInfo);

        // entity
        expect(entityDataItemTagsMap[EntityTag.driveId], 'drive123');
        expect(
            entityDataItemTagsMap[EntityTag.contentType], 'application/json');
        // folder id
        expect(entityDataItemTagsMap[EntityTag.folderId], 'entity123');
        expect(
            entityDataItemTagsMap[EntityTag.parentFolderId], 'parentFolder123');
        expect(
            entityDataItemTagsMap[EntityTag.entityType], EntityTypeTag.folder);
        _validateAppTags(entityDataItemTagsMap, appInfo);
      });

      test('Generates tags for standard a private folder input', () {
        // Define standard ARFSTagsArgs
        var args = ARFSTagsArgs(
          driveId: 'drive123',
          entityId: 'entity123',
          contentType: 'application/json',
          entity: EntityType.folder,
          isPrivate: true,
          parentFolderId: 'parentFolder123',
        );

        var result = tagsGenerator.generateTags(args);

        final dataItemTags = result['data-item'];
        final bundleTags = result['bundle-data-item'];
        final entityTags = result['entity'];

        final dataItemTagsMap = <String, dynamic>{};
        final bundleDataItemTagsMap = <String, dynamic>{};
        final entityDataItemTagsMap = <String, dynamic>{};

        for (var tag in dataItemTags!) {
          dataItemTagsMap[tag.name] = tag.value;
        }

        for (var tag in bundleTags!) {
          bundleDataItemTagsMap[tag.name] = tag.value;
        }

        for (var tag in entityTags!) {
          entityDataItemTagsMap[tag.name] = tag.value;
        }

        // Assert

        // dataItemTags
        expect(dataItemTagsMap[EntityTag.contentType], 'application/json');
        _validateAppTags(dataItemTagsMap, appInfo);

        // bundleTags
        expect(bundleDataItemTagsMap['Tip-Type'], 'data upload');
        _validateAppTags(bundleDataItemTagsMap, appInfo);
        // entity
        expect(entityDataItemTagsMap[EntityTag.driveId], 'drive123');
        expect(entityDataItemTagsMap[EntityTag.contentType],
            'application/octet-stream');
        // folder id
        expect(entityDataItemTagsMap[EntityTag.folderId], 'entity123');
        expect(
            entityDataItemTagsMap[EntityTag.parentFolderId], 'parentFolder123');
        expect(
            entityDataItemTagsMap[EntityTag.entityType], EntityTypeTag.folder);
        _validateAppTags(entityDataItemTagsMap, appInfo);
      });

      test(
          'Generates tags for standard a public folder input with no parent folder',
          () {
        // Define standard ARFSTagsArgs
        var args = ARFSTagsArgs(
          driveId: 'drive123',
          entityId: 'entity123',
          contentType: 'application/json',
          entity: EntityType.folder,
          isPrivate: false,
          parentFolderId: null,
        );

        var result = tagsGenerator.generateTags(args);

        final entityTags = result['entity'];

        final entityDataItemTagsMap = <String, dynamic>{};

        for (var tag in entityTags!) {
          entityDataItemTagsMap[tag.name] = tag.value;
        }

        // Assert
        expect(entityDataItemTagsMap[EntityTag.parentFolderId], isNull);
      });
      test(
          'Generates tags for standard a private folder input with no parent folder',
          () {
        // Define standard ARFSTagsArgs
        var args = ARFSTagsArgs(
          driveId: 'drive123',
          entityId: 'entity123',
          contentType: 'application/json',
          entity: EntityType.folder,
          isPrivate: true,
          parentFolderId: null,
        );

        var result = tagsGenerator.generateTags(args);

        final entityTags = result['entity'];

        final entityDataItemTagsMap = <String, dynamic>{};

        for (var tag in entityTags!) {
          entityDataItemTagsMap[tag.name] = tag.value;
        }

        // Assert
        expect(entityDataItemTagsMap[EntityTag.parentFolderId], isNull);
      });

      test(
          'Generates tags for standard public folder bundle input with CUSTOM bundle tags',
          () {
        var args = ARFSTagsArgs(
          driveId: 'drive123',
          entityId: 'entity123',
          contentType: 'text/plain',
          entity: EntityType.folder,
          isPrivate: false,
          parentFolderId: 'parentFolder123',
          customBundleTags: [
            Tag('custom-tag-name', 'custom-tag-value'),
          ],
        );

        var result = tagsGenerator.generateTags(args);

        final bundleTags = result['bundle-data-item'];

        final bundleDataItemTagsMap = <String, dynamic>{};

        for (var tag in bundleTags!) {
          bundleDataItemTagsMap[tag.name] = tag.value;
        }

        expect(bundleDataItemTagsMap['custom-tag-name'], 'custom-tag-value');
      });
    });

    group('generating for drives', () {
      test('Generates tags for standard a public drive input', () {
        // Define standard ARFSTagsArgs
        var args = ARFSTagsArgs(
          driveId: 'drive123',
          entityId: 'entity123',
          contentType: 'application/json',
          entity: EntityType.folder,
          isPrivate: false,
          parentFolderId: 'parentFolder123',
        );

        var result = tagsGenerator.generateTags(args);

        final dataItemTags = result['data-item'];
        final bundleTags = result['bundle-data-item'];
        final entityTags = result['entity'];

        final dataItemTagsMap = <String, dynamic>{};
        final bundleDataItemTagsMap = <String, dynamic>{};
        final entityDataItemTagsMap = <String, dynamic>{};

        for (var tag in dataItemTags!) {
          dataItemTagsMap[tag.name] = tag.value;
        }

        for (var tag in bundleTags!) {
          bundleDataItemTagsMap[tag.name] = tag.value;
        }

        for (var tag in entityTags!) {
          entityDataItemTagsMap[tag.name] = tag.value;
        }

        // Assert

        // dataItemTags
        expect(dataItemTagsMap[EntityTag.contentType], 'application/json');
        _validateAppTags(dataItemTagsMap, appInfo);

        // bundleTags
        expect(bundleDataItemTagsMap['Tip-Type'], 'data upload');
        _validateAppTags(bundleDataItemTagsMap, appInfo);

        // entity
        expect(entityDataItemTagsMap[EntityTag.driveId], 'drive123');
        expect(
            entityDataItemTagsMap[EntityTag.contentType], 'application/json');
        // folder id
        expect(entityDataItemTagsMap[EntityTag.folderId], 'entity123');
        expect(
            entityDataItemTagsMap[EntityTag.parentFolderId], 'parentFolder123');
        expect(
            entityDataItemTagsMap[EntityTag.entityType], EntityTypeTag.folder);
        _validateAppTags(entityDataItemTagsMap, appInfo);
      });
    });
  });
}

void _validateAppTags(
    Map<String, dynamic> entityDataItemTagsMap, AppInfo appInfo) {
  expect(entityDataItemTagsMap[EntityTag.appVersion], appInfo.version);
  expect(entityDataItemTagsMap[EntityTag.appName], appInfo.appName);
  expect(entityDataItemTagsMap[EntityTag.appPlatform], appInfo.platform);
}

class DumbIOFile implements IOFile {
  @override
  String get contentType => 'text/plain';

  @override
  DateTime get lastModifiedDate => DateTime.now();

  @override
  FutureOr<int> get length => 128;

  @override
  String get name => 'name';

  @override
  Stream<Uint8List> openReadStream([int start = 0, int? end]) {
    // TODO: implement openReadStream
    throw UnimplementedError();
  }

  @override
  String get path => 'path';

  @override
  Future<Uint8List> readAsBytes() {
    return Future.value(Uint8List(128));
  }

  @override
  Future<String> readAsString() {
    return Future.value('readAsString');
  }
}

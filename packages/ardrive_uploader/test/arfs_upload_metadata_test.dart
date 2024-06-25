import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockTag extends Mock implements Tag {}

void main() {
  group('ARFSFolderUploadMetatadata', () {
    late ARFSFolderUploadMetatadata metadata;
    const driveId = 'driveId';
    const parentFolderId = 'parentFolderId';
    const name = 'Test Folder';
    const id = 'id';
    const isPrivate = true;

    setUp(() {
      metadata = ARFSFolderUploadMetatadata(
        driveId: driveId,
        parentFolderId: parentFolderId,
        name: name,
        id: id,
        isPrivate: isPrivate,
      );
    });

    test('constructor initializes correctly', () {
      expect(metadata.driveId, driveId);
      expect(metadata.parentFolderId, parentFolderId);
      expect(metadata.name, name);
      expect(metadata.id, id);
      expect(metadata.isPrivate, isPrivate);
    });

    test('toJson returns correct map', () {
      final json = metadata.toJson();
      expect(json, {'name': name});
    });

    group('ARFSUploadMetadata inherited methods and properties', () {
      test('getEntityMetadataTags returns correct tags', () {
        final mockTag1 = MockTag();

        metadata.setEntityMetadataTags([mockTag1]);

        final tags = metadata.getEntityMetadataTags();

        expect(tags, containsAllInOrder([mockTag1]));

        // then add the cipher tags
        metadata.setCipher(cipher: 'cipher', cipherIv: 'cipherIv');

        final tagsWithCipher = metadata.getEntityMetadataTags();

        expect(
            tagsWithCipher,
            containsAllInOrder([
              mockTag1,
              Tag(EntityTag.cipher, 'cipher'),
              Tag(EntityTag.cipherIv, 'cipherIv')
            ]));
      });

      test(
          'getEntityMetadataTags returns correct tags - ensure cipher and cipherIV will override the previous tags',
          () {
        final mockTag1 = MockTag();

        metadata.setEntityMetadataTags([mockTag1]);

        final tags = metadata.getEntityMetadataTags();

        expect(tags, containsAllInOrder([mockTag1]));

        // then add the cipher tags
        metadata.setCipher(cipher: 'cipher', cipherIv: 'cipherIv');

        final tagsWithCipher = metadata.getEntityMetadataTags();

        expect(
            tagsWithCipher,
            containsAllInOrder([
              mockTag1,
              Tag(EntityTag.cipher, 'cipher'),
              Tag(EntityTag.cipherIv, 'cipherIv')
            ]));

        metadata.setEntityMetadataTags([mockTag1]);

        // Override cipher tags
        metadata.setCipher(cipher: 'cipher2', cipherIv: 'cipherIv2');

        final tagsWithCipher2 = metadata.getEntityMetadataTags();

        expect(
            tagsWithCipher2,
            containsAllInOrder([
              mockTag1,
              Tag(EntityTag.cipher, 'cipher2'),
              Tag(EntityTag.cipherIv, 'cipherIv2')
            ]));
      });

      test('setEntityMetadataTags sets the tags correctly', () {
        final mockTag = MockTag();
        metadata.setEntityMetadataTags([mockTag]);
        expect(metadata.getEntityMetadataTags(), contains(mockTag));
      });

      test('metadataTxId setter and getter work correctly', () {
        const metadataTxId = 'metadataTxId';
        metadata.setMetadataTxId = metadataTxId;
        expect(metadata.metadataTxId, metadataTxId);
      });
    });
    group('ARFSFileUploadMetadata', () {
      late ARFSFileUploadMetadata metadata;
      const size = 12345;
      final lastModifiedDate = DateTime.now();
      const dataContentType = 'application/json';
      const driveId = 'driveId';
      const parentFolderId = 'parentFolderId';
      const name = 'Test File';
      const id = 'id';
      const isPrivate = true;
      const licenseDefinitionTxId = 'licenseDefinitionTxId';
      const licenseAdditionalTags = {'key1': 'value1'};

      setUp(() {
        metadata = ARFSFileUploadMetadata(
          size: size,
          lastModifiedDate: lastModifiedDate,
          dataContentType: dataContentType,
          driveId: driveId,
          parentFolderId: parentFolderId,
          licenseDefinitionTxId: licenseDefinitionTxId,
          licenseAdditionalTags: licenseAdditionalTags,
          name: name,
          id: id,
          isPrivate: isPrivate,
        );
      });

      test('constructor initializes correctly', () {
        expect(metadata.size, size);
        expect(metadata.lastModifiedDate, lastModifiedDate);
        expect(metadata.dataContentType, dataContentType);
        expect(metadata.driveId, driveId);
        expect(metadata.parentFolderId, parentFolderId);
        expect(metadata.licenseDefinitionTxId, licenseDefinitionTxId);
        expect(metadata.licenseAdditionalTags, licenseAdditionalTags);
        expect(metadata.name, name);
        expect(metadata.id, id);
        expect(metadata.isPrivate, isPrivate);
      });

      group('Data tags and cipher tags methods', () {
        test('getDataTags returns correct tags', () {
          final mockTag1 = MockTag();

          metadata.setDataTags([mockTag1]);
          metadata.setEntityMetadataTags([mockTag1]);

          final tags = metadata.getDataTags();
          var entityMetadataTags = metadata.getEntityMetadataTags();

          expect(tags, containsAllInOrder([mockTag1]));
          expect(entityMetadataTags, containsAllInOrder([mockTag1]));

          // Add cipher tags
          metadata.setDataCipher(
            cipher: 'cipher',
            cipherIv: 'cipherIv',
          );

          final tagsWithCipher = metadata.getDataTags();

          metadata.setCipher(cipher: 'cipher', cipherIv: 'cipherIv');

          entityMetadataTags = metadata.getEntityMetadataTags();

          expect(
            tagsWithCipher,
            containsAllInOrder([
              mockTag1,
              Tag(EntityTag.cipher, 'cipher'),
              Tag(EntityTag.cipherIv, 'cipherIv')
            ]),
          );

          expect(
            entityMetadataTags,
            containsAllInOrder([
              Tag(EntityTag.cipher, 'cipher'),
              Tag(EntityTag.cipherIv, 'cipherIv')
            ]),
          );

          // Override data cipher tags
          metadata.setDataCipher(
            cipher: 'cipher2',
            cipherIv: 'cipherIv2',
          );

          // Override cipher tags
          metadata.setCipher(cipher: 'cipher2', cipherIv: 'cipherIv2');

          final tagsWithCipher2 = metadata.getDataTags();

          expect(
            tagsWithCipher2,
            containsAllInOrder([
              mockTag1,
              Tag(EntityTag.cipher, 'cipher2'),
              Tag(EntityTag.cipherIv, 'cipherIv2')
            ]),
          );
        });

        test('setDataTags sets the tags correctly', () {
          final mockTag = MockTag();
          metadata.setDataTags([mockTag]);
          expect(metadata.getDataTags(), contains(mockTag));
        });
      });

      group('Data and license transaction IDs', () {
        test('dataTxId setter and getter work correctly', () {
          const dataTxId = 'dataTxId';
          metadata.updateDataTxId(dataTxId);
          expect(metadata.dataTxId, dataTxId);
        });

        test('licenseTxId setter and getter work correctly', () {
          const licenseTxId = 'licenseTxId';
          metadata.updateLicenseTxId(licenseTxId);
          expect(metadata.licenseTxId, licenseTxId);
        });
      });

      group('toJson method', () {
        test('toJson throws StateError if dataTxId is not set', () {
          expect(() => metadata.toJson(), throwsA(isA<StateError>()));
        });
        test('toJson returns correct map when dataTxId is set', () {
          const dataTxId = 'dataTxId';
          metadata.updateDataTxId(dataTxId);

          final json = metadata.toJson();
          expect(json, {
            'name': name,
            'size': size,
            'lastModifiedDate': lastModifiedDate.millisecondsSinceEpoch,
            'dataContentType': dataContentType,
            'dataTxId': dataTxId,
          });
        });
        test('toJson returns correct map when dataTxId and licenseTxId are set',
            () {
          const dataTxId = 'dataTxId';
          const licenseTxId = 'licenseTxId';
          metadata.updateDataTxId(dataTxId);
          metadata.updateLicenseTxId(licenseTxId);

          final json = metadata.toJson();
          expect(json, {
            'name': name,
            'size': size,
            'lastModifiedDate': lastModifiedDate.millisecondsSinceEpoch,
            'dataContentType': dataContentType,
            'dataTxId': dataTxId,
            'licenseTxId': licenseTxId,
          });
        });
        // TODO: update test to include the correct thumbnail object
        test(
            'toJson returns correct map when dataTxId and licenseTxId and thumbnailTxId are set',
            () {
          const dataTxId = 'dataTxId';
          const licenseTxId = 'licenseTxId';
          metadata.updateDataTxId(dataTxId);
          metadata.updateLicenseTxId(licenseTxId);
          // metadata.updateThumbnailTxId('thumbnailTxId');

          final json = metadata.toJson();
          expect(json, {
            'name': name,
            'size': size,
            'lastModifiedDate': lastModifiedDate.millisecondsSinceEpoch,
            'dataContentType': dataContentType,
            'dataTxId': dataTxId,
            'licenseTxId': licenseTxId,
          });
        });
      });
    });
  });
}

import 'package:ardrive/entities/custom_metadata.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Custom metadata', () {
    test('customMetadataFactory throws for unknown entityType', () {
      const unknownEntityType = 'La magia de la amistad';
      expect(
        () => customMetadataFactory({}, entityType: unknownEntityType),
        throwsException,
      );
    });

    test('customMetadataFactory method removes reserved keys', () {
      final metadata = {
        'name': 'test',
        'reserved': 'reserved',
      };
      final customMetadata =
          customMetadataFactory(metadata, entityType: 'test')();
      expect(customMetadata, '{"name":"test"}');
    });

    test('of drive entity removes expected fields', () {
      final metadata = {
        'name': 'reserved',
        'rootFolderId': 'reserved',
        'Foo': 'Bar',
        'Mati rocks': 'Of course',
        'Dont let': [
          'me down',
          'your dreams be dreams',
          'anyone tell you otherwise'
        ],
      };
      final customMetadata = DriveEntity.customMetaDataFromData(metadata);
      expect(
        customMetadata,
        '{"Foo":"Bar","Mati rocks":"Of course","Dont let":["me down","your dreams be dreams","anyone tell you otherwise"]}',
      );
    });

    test('of folder entity removes expected fields', () {
      final metadata = {
        'name': 'reserved',
        'Foo': 'Bar',
        'Mati rocks': 'Of course',
        'Dont let': [
          'me down',
          'your dreams be dreams',
          'anyone tell you otherwise'
        ],
      };
      final customMetadata = FolderEntity.customMetaDataFromData(metadata);
      expect(
        customMetadata,
        '{"Foo":"Bar","Mati rocks":"Of course","Dont let":["me down","your dreams be dreams","anyone tell you otherwise"]}',
      );
    });

    test('of file entity removes expected fields', () {
      final metadata = {
        'name': 'reserved',
        'size': 'reserved',
        'lastModifiedDate': 'reserved',
        'dataTxId': 'reserved',
        'dataContentType': 'reserved',
        'Foo': 'Bar',
        'Mati rocks': 'Of course',
        'Dont let': [
          'me down',
          'your dreams be dreams',
          'anyone tell you otherwise'
        ],
      };
      final customMetadata = FileEntity.customMetaDataFromData(metadata);
      expect(
        customMetadata,
        '{"Foo":"Bar","Mati rocks":"Of course","Dont let":["me down","your dreams be dreams","anyone tell you otherwise"]}',
      );
    });
  });
}

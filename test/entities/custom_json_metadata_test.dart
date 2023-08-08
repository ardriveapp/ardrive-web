import 'package:ardrive/entities/entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Carry-over of Custom JSON Metadata', () {
    test('for FileEntity', () {
      final fakeEntityJson = {
        // Reserved JSON Metadata
        'name': 'El archivo',
        'size': 123,
        'lastModifiedDate': 12345,
        'dataTxId': 'txId',
        'dataContentType': 'text/plain',

        // Custom JSON Metadata
        'customKey': ['customValue'],
        'anotherOne': {'papá': 'papa'},
        'foo': 'bar',
      };

      final parsedEntity = FileEntity.fromJson(fakeEntityJson);
      final customFields = parsedEntity.customJsonMetadata!;

      expect(customFields['customKey'], ['customValue']);
      expect(customFields['anotherOne'], {'papá': 'papa'});
      expect(customFields['foo'], 'bar');

      expect(customFields['name'], null);
      expect(customFields['size'], null);
      expect(customFields['lastModifiedDate'], null);
      expect(customFields['dataTxId'], null);
      expect(customFields['dataContentType'], null);

      final serializedEntity = parsedEntity.toJson();
      expect(serializedEntity['name'], 'El archivo');
      expect(serializedEntity['size'], 123);
      expect(serializedEntity['lastModifiedDate'], 12345);
      expect(serializedEntity['dataTxId'], 'txId');
      expect(serializedEntity['dataContentType'], 'text/plain');
      expect(serializedEntity['customKey'], ['customValue']);
      expect(serializedEntity['anotherOne'], {'papá': 'papa'});
      expect(serializedEntity['foo'], 'bar');
    });

    test('for FolderEntity', () {
      final fakeEntityJson = {
        // Reserved JSON Metadata
        'name': 'La carpeta',

        // Custom JSON Metadata
        'customKey': ['customValue'],
        'anotherOne': {'papá': 'papa'},
        'foo': 'bar',
      };

      final parsedEntity = FolderEntity.fromJson(fakeEntityJson);
      final customFields = parsedEntity.customJsonMetadata!;

      expect(customFields['customKey'], ['customValue']);
      expect(customFields['anotherOne'], {'papá': 'papa'});
      expect(customFields['foo'], 'bar');

      expect(customFields['name'], null);

      final serializedEntity = parsedEntity.toJson();
      expect(serializedEntity['name'], 'La carpeta');
      expect(serializedEntity['customKey'], ['customValue']);
      expect(serializedEntity['anotherOne'], {'papá': 'papa'});
      expect(serializedEntity['foo'], 'bar');
    });

    test('for DriveEntity', () {
      final fakeEntityJson = {
        // Reserved JSON Metadata
        'name': 'El disko',
        'rootFolderId': 'rootFolderId',

        // Custom JSON Metadata
        'customKey': ['customValue'],
        'anotherOne': {'papá': 'papa'},
        'foo': 'bar',
      };

      final parsedEntity = DriveEntity.fromJson(fakeEntityJson);
      final customFields = parsedEntity.customJsonMetadata!;

      expect(customFields['customKey'], ['customValue']);
      expect(customFields['anotherOne'], {'papá': 'papa'});
      expect(customFields['foo'], 'bar');

      expect(customFields['name'], null);
      expect(customFields['rootFolderId'], null);

      final serializedEntity = parsedEntity.toJson();
      expect(serializedEntity['name'], 'El disko');
      expect(serializedEntity['rootFolderId'], 'rootFolderId');
      expect(serializedEntity['customKey'], ['customValue']);
      expect(serializedEntity['anotherOne'], {'papá': 'papa'});
      expect(serializedEntity['foo'], 'bar');
    });
  });

  group('Carry-over of Custom GQL Tags', () {
    test('for FileEntity', () {});
  });
}

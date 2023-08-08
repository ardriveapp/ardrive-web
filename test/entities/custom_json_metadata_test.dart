import 'package:ardrive/entities/file_entity.dart';
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
        'customKey': 'customValue',
        'foo': 'bar',
      };

      final parsedEntity = FileEntity.fromJson(fakeEntityJson);
      final customFields = parsedEntity.customJsonMetadata!;

      expect(customFields['customKey'], 'customValue');
      expect(customFields['foo'], 'bar');

      final serializedEntity = parsedEntity.toJson();
      expect(serializedEntity['name'], 'El archivo');
      expect(serializedEntity['size'], 123);
      expect(serializedEntity['lastModifiedDate'], 12345);
      expect(serializedEntity['dataTxId'], 'txId');
      expect(serializedEntity['dataContentType'], 'text/plain');
      expect(serializedEntity['customKey'], 'customValue');
      expect(serializedEntity['foo'], 'bar');
    });
  });

  group('Carry-over of Custom GQL Tags', () {
    test('for FileEntity', () {});
  });
}

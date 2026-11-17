import 'package:ardrive/entities/entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> json([Map<String, dynamic> extra = const {}]) => {
        'name': 'app.js',
        'size': 123,
        'lastModifiedDate': 12345,
        'dataTxId': 'txId',
        'dataContentType': 'text/javascript',
        ...extra,
      };

  group('FileEntity dataContentEncoding', () {
    test('is read when present, and size stays as written', () {
      final entity = FileEntity.fromJson(json({'dataContentEncoding': 'gzip'}));

      expect(entity.dataContentEncoding, 'gzip');
      expect(entity.size, 123);
      expect(entity.dataContentType, 'text/javascript');
    });

    test('is null when absent', () {
      final entity = FileEntity.fromJson(json());

      expect(entity.dataContentEncoding, isNull);
      expect(entity.toJson().containsKey('dataContentEncoding'), isFalse);
    });

    test('an unknown extra field does not break parsing', () {
      final entity = FileEntity.fromJson(json({
        'dataContentEncoding': 'gzip',
        'somethingNew': {'a': 1},
      }));

      expect(entity.dataContentEncoding, 'gzip');
      expect(entity.name, 'app.js');
    });

    test('a value that is not a string is ignored, not fatal', () {
      expect(
        FileEntity.fromJson(json({'dataContentEncoding': 5}))
            .dataContentEncoding,
        isNull,
      );
      expect(
        FileEntity.fromJson(json({'dataContentEncoding': ''}))
            .dataContentEncoding,
        isNull,
      );
    });

    test('is written back when the entity is serialized again (a rename)', () {
      final stored = FileEntity.fromJson(json({'dataContentEncoding': 'gzip'}));
      // What the database keeps: the custom metadata string.
      final revision = FileEntity(
        name: 'renamed.js',
        size: stored.size,
        lastModifiedDate: stored.lastModifiedDate,
        dataTxId: stored.dataTxId,
        dataContentType: stored.dataContentType,
      )..customJsonMetadata = stored.customJsonMetadata;

      final written = revision.toJson();
      expect(written['dataContentEncoding'], 'gzip');
      expect(written['size'], 123);
      expect(FileEntity.fromJson(written).dataContentEncoding, 'gzip');
    });
  });
}

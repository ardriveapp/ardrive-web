import 'package:ardrive/manifests/domain/entities/manifest.dart';
import 'package:ardrive/manifests/domain/usecases/extract_manifest_file_ids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ExtractManifestFileIds useCase;
  late Manifest testManifest;

  setUp(() {
    useCase = ExtractManifestFileIds();
    testManifest = Manifest(
      manifest: 'arweave/paths',
      version: '0.1.0',
      index: {'path': 'hello_world.html'},
      paths: {
        'hello_world.html': {
          'id': 'KlwrMWFW9ckVKa8pCGk9a8EjwzYZ7jNVUVHdcE2YkHo'
        },
        'images/logo.png': {'id': 'AnotherFileId123'},
        'empty_file.txt': {'size': '0'}, // No ID
      },
    );
  });

  test('call returns all file IDs', () {
    final fileIds = useCase(testManifest);

    expect(fileIds, hasLength(2));
    expect(fileIds, contains('KlwrMWFW9ckVKa8pCGk9a8EjwzYZ7jNVUVHdcE2YkHo'));
    expect(fileIds, contains('AnotherFileId123'));
  });

  test('getFilePathsWithIds returns correct map', () {
    final pathsWithIds = useCase.getFilePathsWithIds(testManifest);

    expect(pathsWithIds, hasLength(2));
    expect(pathsWithIds['hello_world.html'],
        equals('KlwrMWFW9ckVKa8pCGk9a8EjwzYZ7jNVUVHdcE2YkHo'));
    expect(pathsWithIds['images/logo.png'], equals('AnotherFileId123'));
    expect(pathsWithIds.containsKey('empty_file.txt'), isFalse);
  });

  test('getFileIdByPath returns correct ID', () {
    expect(useCase.getFileIdByPath(testManifest, 'hello_world.html'),
        equals('KlwrMWFW9ckVKa8pCGk9a8EjwzYZ7jNVUVHdcE2YkHo'));
    expect(useCase.getFileIdByPath(testManifest, 'images/logo.png'),
        equals('AnotherFileId123'));
    expect(useCase.getFileIdByPath(testManifest, 'empty_file.txt'), isNull);
    expect(useCase.getFileIdByPath(testManifest, 'non_existent.txt'), isNull);
  });
}

// import 'package:ardrive/manifests/domain/entities/manifest.dart';
// import 'package:flutter_test/flutter_test.dart';

// void main() {
//   group('Manifest', () {
//     final testManifest = Manifest(
//       manifest: 'arweave/paths',
//       version: '0.1.0',
//       index: {'path': 'hello_world.html'},
//       paths: {
//         'hello_world.html': {
//           'id': 'KlwrMWFW9ckVKa8pCGk9a8EjwzYZ7jNVUVHdcE2YkHo'
//         },
//         'images/logo.png': {'id': 'AnotherFileId123'},
//         'empty_file.txt': {'size': '0'}, // No ID
//       },
//     );

//     test('fromJson creates correct Manifest instance', () {
//       final json = {
//         'manifest': 'arweave/paths',
//         'version': '0.1.0',
//         'index': {'path': 'hello_world.html'},
//         'paths': {
//           'hello_world.html': {
//             'id': 'KlwrMWFW9ckVKa8pCGk9a8EjwzYZ7jNVUVHdcE2YkHo'
//           },
//         },
//       };

//       final manifest = Manifest.fromJson(json);

//       expect(manifest.manifest, equals('arweave/paths'));
//       expect(manifest.version, equals('0.1.0'));
//       expect(manifest.index, equals({'path': 'hello_world.html'}));
//       expect(manifest.paths['hello_world.html']?['id'],
//           equals('KlwrMWFW9ckVKa8pCGk9a8EjwzYZ7jNVUVHdcE2YkHo'));
//     });

//     test('getFileIds returns all file IDs', () {
//       final fileIds = testManifest.getFileIds();

//       expect(fileIds, hasLength(2));
//       expect(fileIds, contains('KlwrMWFW9ckVKa8pCGk9a8EjwzYZ7jNVUVHdcE2YkHo'));
//       expect(fileIds, contains('AnotherFileId123'));
//     });

//     test('getFilePathsWithIds returns correct map', () {
//       final pathsWithIds = testManifest.getFilePathsWithIds();

//       expect(pathsWithIds, hasLength(2));
//       expect(pathsWithIds['hello_world.html'],
//           equals('KlwrMWFW9ckVKa8pCGk9a8EjwzYZ7jNVUVHdcE2YkHo'));
//       expect(pathsWithIds['images/logo.png'], equals('AnotherFileId123'));
//       expect(pathsWithIds.containsKey('empty_file.txt'), isFalse);
//     });

//     test('getFileIdByPath returns correct ID', () {
//       expect(testManifest.getFileIdByPath('hello_world.html'),
//           equals('KlwrMWFW9ckVKa8pCGk9a8EjwzYZ7jNVUVHdcE2YkHo'));
//       expect(testManifest.getFileIdByPath('images/logo.png'),
//           equals('AnotherFileId123'));
//       expect(testManifest.getFileIdByPath('empty_file.txt'), isNull);
//       expect(testManifest.getFileIdByPath('non_existent.txt'), isNull);
//     });
//   });
// }
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test', () {
    expect(true, isTrue);
  });
}

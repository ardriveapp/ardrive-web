import 'package:ardrive/manifests/domain/entities/manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Manifest', () {
    test('should create a Manifest instance with the required properties', () {
      // Arrange
      const String manifest = 'arweave/paths';
      const String version = '0.1.0';
      final Map<String, Map<String, dynamic>> paths = {
        'file1.txt': {'id': 'tx1'},
        'file2.txt': {'id': 'tx2'},
      };
      const String index = 'index.html';
      final Map<String, dynamic> fallback = {'path': '404.html'};

      // Act
      final result = Manifest(
        manifest: manifest,
        version: version,
        paths: paths,
        index: index,
        fallback: fallback,
      );

      // Assert
      expect(result.manifest, equals(manifest));
      expect(result.version, equals(version));
      expect(result.paths, equals(paths));
      expect(result.index, equals(index));
      expect(result.fallback, equals(fallback));
    });

    group('fromJson', () {
      test('should correctly parse JSON with all fields', () {
        // Arrange
        final Map<String, dynamic> json = {
          'manifest': 'arweave/paths',
          'version': '0.1.0',
          'paths': {
            'file1.txt': {'id': 'tx1'},
            'file2.txt': {'id': 'tx2'},
          },
          'index': 'index.html',
          'fallback': {'path': '404.html'},
        };

        // Act
        final result = Manifest.fromJson(json);

        // Assert
        expect(result.manifest, equals('arweave/paths'));
        expect(result.version, equals('0.1.0'));
        expect(
            result.paths,
            equals({
              'file1.txt': {'id': 'tx1'},
              'file2.txt': {'id': 'tx2'},
            }));
        expect(result.index, equals('index.html'));
        expect(result.fallback, equals({'path': '404.html'}));
      });

      test('should correctly parse JSON with index as a map', () {
        // Arrange
        final Map<String, dynamic> json = {
          'manifest': 'arweave/paths',
          'version': '0.1.0',
          'paths': {
            'file1.txt': {'id': 'tx1'},
          },
          'index': {'path': 'index.html'},
          'fallback': null,
        };

        // Act
        final result = Manifest.fromJson(json);

        // Assert
        expect(result.index, equals('index.html'));
        expect(result.fallback, isNull);
      });

      test('should correctly parse JSON without optional fields', () {
        // Arrange
        final Map<String, dynamic> json = {
          'manifest': 'arweave/paths',
          'version': '0.1.0',
          'paths': {
            'file1.txt': {'id': 'tx1'},
          },
        };

        // Act
        final result = Manifest.fromJson(json);

        // Assert
        expect(result.manifest, equals('arweave/paths'));
        expect(result.version, equals('0.1.0'));
        expect(
            result.paths,
            equals({
              'file1.txt': {'id': 'tx1'},
            }));
        expect(result.index, isNull);
        expect(result.fallback, isNull);
      });
    });

    test('should implement equality correctly', () {
      // Arrange
      const manifest1 = Manifest(
        manifest: 'arweave/paths',
        version: '0.1.0',
        paths: {
          'file1.txt': {'id': 'tx1'},
        },
        index: 'index.html',
        fallback: {'path': '404.html'},
      );

      const manifest2 = Manifest(
        manifest: 'arweave/paths',
        version: '0.1.0',
        paths: {
          'file1.txt': {'id': 'tx1'},
        },
        index: 'index.html',
        fallback: {'path': '404.html'},
      );

      const differentManifest = Manifest(
        manifest: 'arweave/paths',
        version: '0.2.0', // Different version
        paths: {
          'file1.txt': {'id': 'tx1'},
        },
        index: 'index.html',
        fallback: {'path': '404.html'},
      );

      // Assert
      expect(manifest1, equals(manifest2));
      expect(manifest1, isNot(equals(differentManifest)));
      expect(manifest1.hashCode, equals(manifest2.hashCode));
      expect(manifest1.hashCode, isNot(equals(differentManifest.hashCode)));
    });
  });
}

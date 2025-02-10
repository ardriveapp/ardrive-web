import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/manifests/data/data_sources/manifest_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDownloadService extends Mock implements DownloadService {}

void main() {
  late ManifestDataSource manifestDataSource;
  late MockDownloadService mockDownloadService;

  setUp(() {
    mockDownloadService = MockDownloadService();
    manifestDataSource = ManifestDataSource(mockDownloadService);
  });

  group('downloadAndParseManifest', () {
    const testManifestTxId = 'test-manifest-tx-id';
    final validManifestJson = {
      'manifest': 'arweave/paths',
      'version': '0.2.0',
      'index': {'id': 'index-file-id'},
      'paths': {
        'file1.txt': {'id': 'file1-id'},
        'file2.txt': {'id': 'file2-id'},
      },
      'fallback': {'id': 'fallback-file-id'},
    };

    test('successfully downloads and parses valid manifest', () async {
      // Arrange
      final manifestBytes =
          Uint8List.fromList(utf8.encode(json.encode(validManifestJson)));
      when(() => mockDownloadService.download(testManifestTxId, true))
          .thenAnswer((_) async => manifestBytes);

      // Act
      final result =
          await manifestDataSource.downloadAndParseManifest(testManifestTxId);

      // Assert
      expect(result, equals(validManifestJson));
      verify(() => mockDownloadService.download(testManifestTxId, true))
          .called(1);
    });

    test('throws ManifestDownloadException when download fails', () async {
      // Arrange
      when(() => mockDownloadService.download(testManifestTxId, true))
          .thenThrow(Exception('Network error'));

      // Act & Assert
      expect(
        () => manifestDataSource.downloadAndParseManifest(testManifestTxId),
        throwsA(isA<ManifestDownloadException>()),
      );
    });

    // test('throws ManifestParseException when manifest is invalid JSON',
    //     () async {
    //   // Arrange
    //   final invalidJson = Uint8List.fromList(utf8.encode('invalid json'));
    //   when(() => mockDownloadService.download(testManifestTxId, true))
    //       .thenAnswer((_) async => invalidJson);

    //   // Act & Assert
    //   expect(
    //     () => manifestDataSource.downloadAndParseManifest(testManifestTxId),
    //     throwsA(isA<ManifestParseException>()),
    //   );
    // });

    // test('throws ManifestParseException when manifest structure is invalid',
    //     () async {
    //   // Arrange
    //   final invalidManifest = {'invalid': 'structure'};
    //   final manifestBytes =
    //       Uint8List.fromList(utf8.encode(json.encode(invalidManifest)));
    //   when(() => mockDownloadService.download(testManifestTxId, true))
    //       .thenAnswer((_) async => manifestBytes);

    //   // Act & Assert
    //   expect(
    //     () => manifestDataSource.downloadAndParseManifest(testManifestTxId),
    //     throwsA(isA<ManifestParseException>()),
    //   );
    // });
  });

  group('extractFileIds', () {
    test('extracts all file IDs from valid manifest', () {
      // Arrange
      final manifestJson = {
        'manifest': 'arweave/paths',
        'version': '0.2.0',
        'index': {'id': 'index-file-id'},
        'paths': {
          'file1.txt': {'id': 'file1-id'},
          'file2.txt': {'id': 'file2-id'},
        },
        'fallback': {'id': 'fallback-file-id'},
      };

      // Act
      final fileIds = manifestDataSource.extractFileIds(manifestJson);

      // Assert
      expect(
          fileIds,
          containsAll(
              ['index-file-id', 'file1-id', 'file2-id', 'fallback-file-id']));
      expect(fileIds.length, equals(4));
    });

    test('handles manifest without optional fields', () {
      // Arrange
      final manifestJson = {
        'manifest': 'arweave/paths',
        'version': '0.2.0',
        'paths': {
          'file1.txt': {'id': 'file1-id'},
        },
      };

      // Act
      final fileIds = manifestDataSource.extractFileIds(manifestJson);

      // Assert
      expect(fileIds, equals(['file1-id']));
      expect(fileIds.length, equals(1));
    });

    test('throws ManifestParseException when paths structure is invalid', () {
      // Arrange
      final invalidManifest = {
        'manifest': 'arweave/paths',
        'version': '0.2.0',
        'paths': 'invalid',
      };

      // Act & Assert
      expect(
        () => manifestDataSource.extractFileIds(invalidManifest),
        throwsA(isA<ManifestParseException>()),
      );
    });
  });
}

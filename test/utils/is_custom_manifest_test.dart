import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/utils/is_custom_manifest.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockIOFile extends Mock implements IOFile {}

void main() {
  late MockIOFile mockFile;

  setUp(() {
    mockFile = MockIOFile();
    registerFallbackValue(0);
    registerFallbackValue(100);
  });

  group('isCustomManifest', () {
    test('returns true when file is JSON and contains arweave/paths', () async {
      // Arrange
      const jsonContent =
          '{"manifest":"arweave/paths","version":"0.1.0","index":{"path":"hello_world.html"},"paths":{"hello_world.html":{"id":"KlwrMWFW9ckVKa8pCGk9a8EjwzYZ7jNVUVHdcE2YkHo"}}}';
      final bytes = utf8.encode(jsonContent);

      when(() => mockFile.contentType).thenReturn('application/json');
      when(() => mockFile.openReadStream(any(), any()))
          .thenAnswer((_) => Stream.value(Uint8List.fromList(bytes)));
      when(() => mockFile.length).thenReturn(bytes.length);
      // Act
      final result = await isCustomManifest(mockFile);

      // Assert
      expect(result, true);
      verify(() => mockFile.openReadStream(0, 100)).called(1);
    });

    test('returns false when file is JSON but does not contain arweave/paths',
        () async {
      // Arrange
      const jsonContent = '{"version": 1, "type": "regular"}';
      final bytes = utf8.encode(jsonContent);

      when(() => mockFile.contentType).thenReturn('application/json');
      when(() => mockFile.openReadStream(any(), any()))
          .thenAnswer((_) => Stream.value(Uint8List.fromList(bytes)));
      when(() => mockFile.length).thenReturn(bytes.length);

      // Act
      final result = await isCustomManifest(mockFile);

      // Assert
      expect(result, false);
      verify(() => mockFile.openReadStream(0, 33)).called(1);
    });

    test('returns false when file is not JSON', () async {
      // Arrange
      when(() => mockFile.contentType).thenReturn('text/plain');
      when(() => mockFile.length).thenReturn(0);
      // Act
      final result = await isCustomManifest(mockFile);

      // Assert
      expect(result, false);
      verifyNever(() => mockFile.openReadStream(any(), any()));
    });

    test('returns false when stream is empty', () async {
      // Arrange
      when(() => mockFile.contentType).thenReturn('application/json');
      when(() => mockFile.openReadStream(any(), any()))
          .thenAnswer((_) => Stream.value(Uint8List(0)));
      when(() => mockFile.length).thenReturn(0);
      // Act
      final result = await isCustomManifest(mockFile);

      // Assert
      expect(result, false);
      verify(() => mockFile.openReadStream(0, 0)).called(1);
    });
  });
}

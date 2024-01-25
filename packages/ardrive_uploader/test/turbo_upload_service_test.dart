import 'dart:typed_data';

import 'package:ardrive_uploader/src/turbo_chunked_upload_service.dart';
import 'package:test/test.dart';

void main() {
  group('TurboUploadService', () {
    group('streamToChunks', () {
      test('should return a stream of chunks of the specified size', () async {
        Stream<Uint8List> largeStream = Stream.fromIterable([
          Uint8List.fromList(List.generate(10, (i) => i)),
          Uint8List.fromList(List.generate(2, (i) => 10 + i)),
        ]);

        final chunks = await streamToChunks(largeStream, 5).toList();
        expect(chunks.length, 3); // 12 bytes in total, 3 chunks
        expect(chunks[0].length, 5); // First chunk is 5 bytes
        expect(chunks[1].length, 5); // Second chunk is 5 bytes
        expect(chunks[2].length, 2); // Third chunk is 2 bytes
      });

      test(
          'should return one chunk if the stream is smaller than the chunk size',
          () async {
        Stream<Uint8List> smallStream = Stream.fromIterable([
          Uint8List.fromList(List.generate(2, (i) => i)),
        ]);

        final chunks = await streamToChunks(smallStream, 5).toList();
        expect(chunks.length, 1); // 2 bytes in total, 1 chunk
        expect(chunks[0].length, 2); // First chunk is 2 bytes
      });

      test('should return an empty stream if the input stream is empty',
          () async {
        Stream<Uint8List> emptyStream = Stream.fromIterable([]);
        final chunks = await streamToChunks(emptyStream, 5).toList();
        expect(chunks.length, 0); // empty stream, 0 chunks
      });
    });
  });
}

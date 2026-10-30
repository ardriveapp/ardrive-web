@TestOn('browser')
library;

// ignore: avoid_web_libraries_in_flutter
import 'dart:html';
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_util' as js_util;
import 'dart:typed_data';

// The app reaches file_picker through ardrive_io, whose web reader uses this.
// ignore: depend_on_referenced_packages
import 'package:file_picker/blob_reader.dart';
import 'package:flutter_test/flutter_test.dart';

/// A file whose contents changed after it was picked can't be read: the
/// browser fires `error` and `loadend`, never `load`. The readers waited on
/// `load` alone, so keyfile log in and uploads waited for ever.
void main() {
  test('reads a file', () async {
    final blob = Blob([
      Uint8List.fromList([1, 2, 3])
    ]);
    expect(await readBlobBytes(blob), [1, 2, 3]);
  });

  test('a file that changed after it was picked fails, rather than waiting',
      () async {
    final file = await _fileThatChangedAfterItWasPicked();

    await expectLater(
      readBlobBytes(file),
      throwsA(isA<BlobReadException>()
          .having((e) => e.name, 'name', 'NotReadableError')),
    );
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('a stopped read fails', () async {
    final reader = FileReader();
    final read = readBlobBytes(
      Blob([Uint8List(8 * 1024 * 1024)]),
      reader: reader,
    );
    reader.abort();

    await expectLater(read, throwsA(isA<BlobReadException>()));
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('a reader is reused for the chunks of one file', () async {
    final reader = FileReader();
    final blob = Blob([Uint8List.fromList(List.generate(10, (i) => i))]);
    expect(
        await readBlobBytes(blob.slice(0, 5), reader: reader), [0, 1, 2, 3, 4]);
    expect(await readBlobBytes(blob.slice(5, 10), reader: reader),
        [5, 6, 7, 8, 9]);
  });
}

/// A file from the origin private file system, written again after it was
/// taken: the snapshot no longer matches the disk.
Future<File> _fileThatChangedAfterItWasPicked() async {
  final storage = js_util.getProperty<Object>(window.navigator, 'storage');
  final root = await js_util
      .promiseToFuture<Object>(js_util.callMethod(storage, 'getDirectory', []));
  final handle = await js_util
      .promiseToFuture<Object>(js_util.callMethod(root, 'getFileHandle', [
    'blob-reader-test.txt',
    js_util.jsify({'create': true})
  ]));

  Future<void> write(String text) async {
    final writable = await js_util.promiseToFuture<Object>(
        js_util.callMethod(handle, 'createWritable', []));
    await js_util
        .promiseToFuture<void>(js_util.callMethod(writable, 'write', [text]));
    await js_util
        .promiseToFuture<void>(js_util.callMethod(writable, 'close', []));
  }

  await write('the first contents');
  final file = await js_util
      .promiseToFuture<File>(js_util.callMethod(handle, 'getFile', []));
  // Make sure the modified time moves on.
  await Future<void>.delayed(const Duration(milliseconds: 20));
  await write('changed after it was picked');
  return file;
}

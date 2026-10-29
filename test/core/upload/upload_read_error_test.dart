import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
// ignore: implementation_imports
import 'package:ardrive_uploader/src/data_bundler.dart';
// ignore: implementation_imports
import 'package:ardrive_uploader/src/upload_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';

class _MockUploadFileStrategy extends Mock implements UploadFileStrategy {}

class _MockFolderStrategy extends Mock
    implements UploadFolderStructureStrategy {}

class _MockThumbnailStrategy extends Mock implements UploadThumbnailStrategy {}

class _MockDataBundler extends Mock implements DataBundler {}

/// A chosen file the browser can no longer read, as when it changed after it
/// was picked: every read fails, as the web readers now make it.
class _UnreadableFile extends Fake implements IOFile {
  @override
  String get name => 'notes.txt';

  @override
  String get path => 'notes.txt';

  @override
  String get contentType => 'text/plain';

  @override
  DateTime get lastModifiedDate => DateTime(2026);

  @override
  FutureOr<int> get length => 10;

  @override
  Future<Uint8List> readAsBytes() =>
      Future.error(Exception('NotReadableError'));

  @override
  Stream<Uint8List> openReadStream([int start = 0, int? end]) =>
      Stream.error(Exception('NotReadableError'));
}

/// A file that can't be read during an upload ends as a failed upload, which
/// the upload form shows as a failure it can close, never as a stall.
void main() {
  test('a file that cannot be read fails its upload', () async {
    final strategy = _MockUploadFileStrategy();
    final controller = UploadController(
      StreamController<UploadProgress>(),
      UploadDispatcher(
        uploadStrategy: strategy,
        dataBundler: _MockDataBundler(),
        uploadFolderStrategy: _MockFolderStrategy(),
        uploadThumbnailStrategy: _MockThumbnailStrategy(),
      ),
      numOfWorkers: 1,
      maxTasksPerWorker: 1,
    );
    final metadata = ARFSFileUploadMetadata(
      size: 10,
      lastModifiedDate: DateTime(2026),
      dataContentType: 'text/plain',
      driveId: 'drive',
      parentFolderId: 'folder',
      name: 'notes.txt',
      id: 'file',
      isPrivate: false,
    );
    final failed = Completer<List<UploadTask>>();
    final done = <List<UploadTask>>[];
    controller.onError(failed.complete);
    controller.onDone(done.add);
    controller.onProgressChange((_) {});
    controller.addTask(FileUploadTask(
      file: _UnreadableFile(),
      metadata: metadata,
      content: [metadata],
      type: UploadType.turbo,
      uploadThumbnail: false,
    ));

    controller.sendTasks(getTestWallet());

    final tasks = await failed.future.timeout(const Duration(seconds: 10));
    expect(tasks.single.status, UploadStatus.failed);
    // Signing reads the file first, and arweave-dart wraps the read error
    // in its own (DeepHashStreamError), which keeps no message.
    expect(tasks.single.error, isNotNull);
    expect(done, isEmpty);
    verifyZeroInteractions(strategy);
  });
}

import 'package:ardrive/blocs/upload/upload_progress_summary.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockIOFile extends Mock implements IOFile {}

/// The data item that carries a file, which is larger than the file.
class _UploadItem extends UploadItem<Object> {
  _UploadItem(int size) : super(size: size, data: Object());
}

ARFSFileUploadMetadata _file(String name, int size) => ARFSFileUploadMetadata(
      size: size,
      lastModifiedDate: DateTime.utc(2026, 10, 1),
      dataContentType: 'text/html',
      driveId: 'drive',
      parentFolderId: 'folder',
      name: name,
      id: name,
      isPrivate: false,
    );

FileUploadTask _fileTask(
  ARFSFileUploadMetadata file, {
  UploadStatus status = UploadStatus.inProgress,
  double progress = 0,
}) =>
    FileUploadTask(
      id: file.id,
      file: _MockIOFile(),
      metadata: file,
      content: [file],
      type: UploadType.turbo,
      uploadThumbnail: false,
      status: status,
      progress: progress,
      uploadItem: _UploadItem(file.size + 1147),
    );

FolderUploadTask _folderTask({UploadStatus status = UploadStatus.complete}) =>
    FolderUploadTask(
      id: 'folders',
      folders: const [],
      content: [
        ARFSFolderUploadMetatadata(
          driveId: 'drive',
          name: 'site',
          id: 'site',
          isPrivate: false,
        ),
      ],
      type: UploadType.turbo,
      status: status,
      progress: 1,
      uploadItem: _UploadItem(1443),
    );

UploadProgress _progress(List<UploadTask> tasks) =>
    UploadProgress.notStarted().copyWith(
      tasks: {for (final task in tasks) task.id: task},
    );

void main() {
  final index = _file('index.html', 3133);
  final style = _file('style.css', 2120);
  final script = _file('app.js', 4730);

  group('UploadProgressSummary', () {
    test('counts files only, at their own size', () {
      final summary = UploadProgressSummary.from(_progress([
        _folderTask(),
        _fileTask(index),
        _fileTask(style),
        _fileTask(script),
      ]));

      // The confirm step says 3 files and the sum of their sizes. The new
      // folder and each data item's own overhead are left out.
      expect(summary.numberOfFiles, 3);
      expect(summary.totalSize, 3133 + 2120 + 4730);
    });

    test('measures what is sent at the file size', () {
      final summary = UploadProgressSummary.from(_progress([
        _fileTask(index, progress: 0.5),
        _fileTask(style, status: UploadStatus.complete, progress: 1),
      ]));

      expect(summary.totalUploaded, (3133 * 0.5).ceil() + 2120);
      expect(summary.numberOfUploadedFiles, 1);
      expect(summary.percent, 70);
    });

    test('stays below 100% while a file is still finalizing', () {
      final summary = UploadProgressSummary.from(_progress([
        _folderTask(),
        _fileTask(index, status: UploadStatus.complete, progress: 1),
        _fileTask(style, status: UploadStatus.complete, progress: 1),
        _fileTask(script, status: UploadStatus.finalizing, progress: 1),
      ]));

      expect(summary.numberOfUploadedFiles, 2);
      expect(summary.totalUploaded, summary.totalSize);
      expect(summary.percent, 99);
    });

    test('reaches 100% when every task is complete', () {
      final summary = UploadProgressSummary.from(_progress([
        _folderTask(),
        _fileTask(index, status: UploadStatus.complete, progress: 1),
        _fileTask(style, status: UploadStatus.complete, progress: 1),
      ]));

      expect(summary.numberOfUploadedFiles, 2);
      expect(summary.numberOfFiles, 2);
      expect(summary.percent, 100);
    });

    test('counts tasks when there are no bytes to count', () {
      final summary = UploadProgressSummary.from(_progress([
        _folderTask(),
        _folderTask(status: UploadStatus.inProgress).copyWith(id: 'more'),
      ]));

      expect(summary.numberOfFiles, 0);
      expect(summary.percent, 50);
    });

    test('is 0% before any task is known', () {
      final summary = UploadProgressSummary.from(UploadProgress.notStarted());

      expect(summary.numberOfFiles, 0);
      expect(summary.percent, 0);
    });
  });
}

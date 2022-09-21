import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_downloader/flutter_downloader.dart';

/// Perform a download in background
///
/// `donwloadFile` downloads a file from `downloadUrl` and saves at the application
/// directory.
///
/// Cancel the current download with `cancelDownload`, if more than one download is
/// running at the time, it will only cancel the current one.
/// 
// TODO: Add an interface for this class and implement a Web and mobile specific downloader 
class ArDriveDownloader {
  late String _currentTaskId;

  String get currentTaskId => _currentTaskId;

  Stream<int> downloadFile(String downloadUrl, String fileName) async* {
    final downloadDir = await getDefaultDownloadDir();

    final taskId = await FlutterDownloader.enqueue(
      url: downloadUrl,
      savedDir: downloadDir,
      fileName: fileName,
      saveInPublicStorage: true,
      showNotification: true,
      openFileFromNotification: false,
    );

    _currentTaskId = taskId!;

    final progress = _handleProgress(taskId);

    FlutterDownloader.loadTasksWithRawQuery(
      query: 'SELECT * FROM task WHERE taskId=$taskId',
    );

    yield* progress;
  }

  Stream<int> _handleProgress(String taskId) {
    ReceivePort _port = ReceivePort();
    StreamController<int> controller = StreamController<int>();
    IsolateNameServer.registerPortWithName(
        _port.sendPort, 'downloader_send_port');
    _port.listen((dynamic data) {
      String id = data[0];
      DownloadTaskStatus status = data[1];
      int progress = data[2];
      debugPrint('Donwload $taskId status: ' + status.toString());
      debugPrint('Download progress: ' + progress.toString());

      /// canceled and failed downloads
      if (status != DownloadTaskStatus.running) {
        controller.close();
        IsolateNameServer.removePortNameMapping('downloader_send_port');
        return;
      }

      /// only track the progress of current task id
      if (id == taskId) {
        controller.sink.add(progress);
        // download finished
        if (progress == 100) {
          controller.close();
          IsolateNameServer.removePortNameMapping('downloader_send_port');
          return;
        }
      }
    });

    return controller.stream;
  }

  static Future<void> initialize() async {
    // Plugin must be initialized before using
    await FlutterDownloader.initialize(debug: !kReleaseMode);

    FlutterDownloader.registerCallback(downloadCallback);
  }

  void cancelDownload() {
    FlutterDownloader.cancel(taskId: _currentTaskId);
  }

  Future<void> openCurrentDownload() async {
    final canOpen = await FlutterDownloader.open(taskId: _currentTaskId);

    if (!canOpen) {
      throw UnsupportedFileExtension();
    }
  }
}

@pragma('vm:entry-point')
void downloadCallback(String id, DownloadTaskStatus status, int progress) {
  final SendPort send =
      IsolateNameServer.lookupPortByName('downloader_send_port')!;
  send.send([id, status, progress]);
}

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
class ArDriveMobileDownloader {
  late String _currentTaskId;

  String get currentTaskId => _currentTaskId;

  Stream<int> downloadFile(
      String downloadUrl, String fileName, String? contentType) async* {
    await requestPermissions();
    await verifyPermissions();

    final downloadDir = await getDefaultMobileDownloadDir();
    final saveFileName =
        await nonexistentFileName(downloadDir, fileName, contentType);

    final taskId = await FlutterDownloader.enqueue(
      url: downloadUrl,
      savedDir: downloadDir,
      fileName: saveFileName,
      saveInPublicStorage: true,
      showNotification: true,
      openFileFromNotification: false,
    );

    _currentTaskId = taskId!;

    final progress = _handleProgress(taskId);

    FlutterDownloader.loadTasksWithRawQuery(
      query: 'SELECT * FROM task WHERE task_id="$taskId"',
    );

    yield* progress;
  }

  Stream<int> _handleProgress(String taskId) {
    ReceivePort port = ReceivePort();
    StreamController<int> controller = StreamController<int>();

    /// Remove previous port and track only one download
    IsolateNameServer.removePortNameMapping('downloader_send_port');

    IsolateNameServer.registerPortWithName(
        port.sendPort, 'downloader_send_port');

    port.listen((dynamic data) {
      DownloadTaskStatus status = DownloadTaskStatus.values[data[1]];
      int progress = data[2];

      /// only track the progress of current task id
      if (status == DownloadTaskStatus.enqueued) {
        controller.sink.add(0);
      } else if (status == DownloadTaskStatus.running) {
        debugPrint('Download progress: $progress');
        controller.sink.add(progress);
      } else if (status == DownloadTaskStatus.complete) {
        controller.sink.add(100);
        debugPrint('background download completed');
        controller.close();
      } else {
        /// canceled and failed downloads
        debugPrint('background download finished with status: $status');
        controller.close();
      }
    });

    return controller.stream;
  }

  static Future<void> initialize() async {
    if (kIsWeb) {
      return;
    }

    // Plugin must be initialized before using
    await FlutterDownloader.initialize(debug: kDebugMode);

    /// As we don't handle unfinished downloads
    /// we should cancel all when start
    await FlutterDownloader.cancelAll();

    FlutterDownloader.registerCallback(downloadCallback);
  }

  Future<void> cancelDownload() async {
    if (kIsWeb) {
      return;
    }

    IsolateNameServer.removePortNameMapping('downloader_send_port');

    debugPrint('Current task id: $_currentTaskId');

    await FlutterDownloader.cancel(taskId: _currentTaskId);
  }

  Future<void> openCurrentDownload() async {
    final canOpen = await FlutterDownloader.open(taskId: _currentTaskId);

    if (!canOpen) {
      throw UnsupportedFileExtension();
    }
  }
}

@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final SendPort send =
      IsolateNameServer.lookupPortByName('downloader_send_port')!;
  debugPrint('sending message isolate downloader');
  send.send([id, status, progress]);
}

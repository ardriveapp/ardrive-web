import 'dart:async';

import 'package:uuid/uuid.dart';

import '../ardrive_uploader.dart';

abstract class UploadTask {
  abstract final String id;
  abstract final DataItemResultWithContents? dataItem;
  abstract double progress;
  abstract bool isProgressAvailable;
  abstract UploadStatus status;

  factory UploadTask({
    DataItemResultWithContents? dataItemResult,
    bool isProgressAvailable = true,
    UploadStatus status = UploadStatus.notStarted,
  }) {
    return _UploadTask(
      dataItemResult,
      isProgressAvailable: isProgressAvailable,
      status,
      const Uuid().v4(),
    );
  }

  // copyWith
  UploadTask copyWith({
    DataItemResultWithContents? dataItem,
    double? progress,
    bool? isProgressAvailable,
    UploadStatus? status,
  });
}

class _UploadTask implements UploadTask {
  @override
  final DataItemResultWithContents? dataItem;

  @override
  double progress = 0;

  @override
  final String id;

  @override
  bool isProgressAvailable = true;

  _UploadTask(
    this.dataItem,
    this.status,
    this.id, {
    this.isProgressAvailable = true,
  });

  @override
  UploadStatus status;

  @override
  UploadTask copyWith({
    DataItemResultWithContents? dataItem,
    double? progress,
    bool? isProgressAvailable,
    UploadStatus? status,
    String? id,
  }) {
    return _UploadTask(
      dataItem ?? this.dataItem,
      status ?? this.status,
      id ?? this.id,
      isProgressAvailable: isProgressAvailable ?? this.isProgressAvailable,
    );
  }
}

// TODO: Review this file
abstract class UploadController {
  abstract final ARFSUploadMetadata metadata;

  abstract final List<UploadTask> tasks;

  Future<void> close();
  void cancel();
  void onCancel();
  // TODO: Return a list of tasks.
  void onDone(Function(List<UploadTask> tasks) callback);
  void onError(Function() callback);
  void updateProgress({
    UploadTask? task,
  });
  void onProgressChange(Function(UploadProgress progress) callback);

  bool get isPossibleGetProgress;
  set isPossibleGetProgress(bool value);

  factory UploadController(
    ARFSUploadMetadata metadata,
    StreamController<UploadProgress> progressStream,
  ) {
    return _UploadController(
      metadata: metadata,
      progressStream: progressStream,
    );
  }
}

class _UploadController implements UploadController {
  final StreamController<UploadProgress> _progressStream;

  _UploadController({
    required this.metadata,
    required StreamController<UploadProgress> progressStream,
  }) : _progressStream = progressStream {
    init();
  }

  bool _isCanceled = false;
  bool get isCanceled => _isCanceled;

  void init() {
    _isCanceled = false;
    late StreamSubscription subscription;

    subscription = _progressStream.stream.listen(
      (event) async {
        _onProgressChange!(event);

        if (_uploadProgress.progress == 1) {
          await close();
          return;
        }
      },
      onDone: () {
        print('Done upload');
        _onDone(tasks);
        subscription.cancel();
      },
      onError: (err) {
        print('Error: $err');
        subscription.cancel();
      },
    );
  }

  @override
  Future<void> close() async {
    await _progressStream.close();
  }

  @override
  void cancel() {
    _isCanceled = true;
    _progressStream.close();
  }

  @override
  void onCancel() {}

  @override
  void onDone(Function(List<UploadTask> tasks) callback) {
    _onDone = callback;
  }

  @override
  void updateProgress({
    UploadTask? task,
  }) {
    if (_progressStream.isClosed) {
      return;
    }

    if (task != null) {
      final index = tasks.indexWhere(
        (element) => element.id == task.id,
      );

      print('Index: $index');

      if (index == -1) {
        tasks.add(task);
      } else {
        tasks[index] = task;
      }

      _uploadProgress = _uploadProgress.copyWith(
        task: tasks,
        progress: calculateTotalProgress(tasks),
        totalSize: totalSize(tasks),
      );

      _progressStream.add(
        // TODO:
        _uploadProgress,
      );
    }

    print('Progress: ${_uploadProgress.progress}');

    return;
  }

  UploadProgress _uploadProgress = UploadProgress(
    progress: 0,
    totalSize: 0,
    task: [],
  );

  @override
  void onError(Function() callback) {
    // TODO: implement onError
  }

  @override
  void onProgressChange(Function(UploadProgress progress) callback) {
    _onProgressChange = callback;
  }

  void Function(UploadProgress progress)? _onProgressChange = (progress) {};

  void Function(List<UploadTask> tasks) _onDone = (List<UploadTask> tasks) {
    print('Upload Finished');
  };

  @override
  final ARFSUploadMetadata metadata;

  @override
  bool get isPossibleGetProgress => _isPossibleGetProgress;

  @override
  set isPossibleGetProgress(bool value) => _isPossibleGetProgress = value;

  bool _isPossibleGetProgress = true;

  @override
  final List<UploadTask> tasks = [];

  double calculateTotalProgress(List<UploadTask> tasks) {
    double totalProgress = 0.0;

    for (var task in tasks) {
      if (task.dataItem == null) {
        continue;
      }

      if (task.isProgressAvailable) {
        totalProgress +=
            (task.progress * task.dataItem!.dataItemResult.dataItemSize);
      }
    }

    return (totalSize(tasks) == 0) ? 0.0 : totalProgress / totalSize(tasks);
  }

  int totalSize(List<UploadTask> tasks) {
    int totalSize = 0;

    for (var task in tasks) {
      if (task.dataItem != null) {
        totalSize += task.dataItem!.dataItemResult.dataItemSize;
      }
    }

    return totalSize;
  }
}

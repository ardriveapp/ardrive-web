import 'dart:async';

import 'package:arweave/arweave.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';

import '../ardrive_uploader.dart';

abstract class _UploadTask<T> {
  abstract final String id;
  abstract final DataItemResult? dataItem;
  abstract final List<ARFSUploadMetadata>? content;
  abstract double progress;
  abstract bool isProgressAvailable;
  abstract UploadStatus status;

  UploadTask copyWith({
    DataItemResult? dataItem,
    double? progress,
    bool? isProgressAvailable,
    UploadStatus? status,
  });
}

class UploadTask implements _UploadTask<ARFSUploadMetadata> {
  @override
  final DataItemResult? dataItem;

  @override
  final List<ARFSUploadMetadata>? content;

  @override
  double progress = 0;

  @override
  final String id;

  @override
  bool isProgressAvailable = true;

  UploadTask({
    this.dataItem,
    this.isProgressAvailable = true,
    this.status = UploadStatus.notStarted,
    this.content,
    String? id,
  }) : id = id ?? const Uuid().v4();

  @override
  UploadStatus status;

  @override
  UploadTask copyWith({
    DataItemResult? dataItem,
    double? progress,
    bool? isProgressAvailable,
    UploadStatus? status,
    String? id,
    List<ARFSUploadMetadata>? content,
  }) {
    return UploadTask(
      dataItem: dataItem ?? this.dataItem,
      content: content ?? this.content,
      id: id ?? this.id,
      isProgressAvailable: isProgressAvailable ?? this.isProgressAvailable,
      status: status ?? this.status,
    );
  }
}

// TODO: Review this file
abstract class UploadController {
  abstract final Map<String, UploadTask> tasks;

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

  factory UploadController(
    StreamController<UploadProgress> progressStream,
  ) {
    return _UploadController(
      progressStream: progressStream,
    );
  }
}

class _UploadController implements UploadController {
  final StreamController<UploadProgress> _progressStream;

  _UploadController({
    required StreamController<UploadProgress> progressStream,
  }) : _progressStream = progressStream {
    init();
  }

  bool _isCanceled = false;
  bool get isCanceled => _isCanceled;

  DateTime? _start;
  void init() {
    _isCanceled = false;
    late StreamSubscription subscription;

    subscription =
        _progressStream.stream.debounceTime(Duration(milliseconds: 50)).listen(
      (event) async {
        _start ??= DateTime.now();

        _onProgressChange!(event);

        if (_uploadProgress.progress == 1) {
          await close();
          return;
        }
      },
      onDone: () {
        print('Done upload');
        _onDone(tasks.values.toList());
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
      tasks[task.id] = task;

      final taskList = tasks.values.toList();

      _uploadProgress = _uploadProgress.copyWith(
        task: taskList,
        progress: calculateTotalProgress(taskList),
        totalSize: totalSize(taskList),
        totalUploaded: totalUploaded(taskList),
        startTime: _start,
      );

      _progressStream.add(_uploadProgress);
    }

    return;
  }

  UploadProgress _uploadProgress = UploadProgress(
    progress: 0,
    totalSize: 0,
    task: [],
    totalUploaded: 0,
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
  final Map<String, UploadTask> tasks = {};

  // CALCULATE BASED ON TOTAL SIZE NOT ONLY ON THE NUMBER OF TASKS
  double calculateTotalProgress(List<UploadTask> tasks) {
    // double totalProgress = 0.0;

    // for (var task in tasks) {
    //   if (task.dataItem == null) {
    //     totalProgress += 0;
    //     continue;
    //   }

    //   if (task.isProgressAvailable) {
    //     totalProgress += (task.progress * task.dataItem!.dataItemSize);
    //   }
    // }

    // return (totalSize(tasks) == 0) ? 0.0 : totalProgress / totalSize(tasks);
    return tasks
            .map((e) => e.progress)
            .reduce((value, element) => value + element) /
        tasks.length;
  }

  int totalUploaded(List<UploadTask> tasks) {
    int totalUploaded = 0;

    for (var task in tasks) {
      if (task.dataItem != null) {
        totalUploaded += (task.progress * task.dataItem!.dataItemSize).toInt();
      }
    }

    return totalUploaded;
  }

  int totalSize(List<UploadTask> tasks) {
    int totalSize = 0;

    for (var task in tasks) {
      if (task.dataItem != null) {
        totalSize += task.dataItem!.dataItemSize;
      }
    }

    return totalSize;
  }
}

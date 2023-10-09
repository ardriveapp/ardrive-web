import 'dart:async';

import 'package:ardrive_uploader/src/streamed_upload.dart';
import 'package:arweave/arweave.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';

import '../ardrive_uploader.dart';

abstract class UploadItem<T> {
  final int size;
  final T data;

  UploadItem({required this.size, required this.data});
}

class BundleDataItemUploadItem extends UploadItem<DataItemResult> {
  BundleDataItemUploadItem({required int size, required DataItemResult data})
      : super(size: size, data: data);
}

class BundleTransactionUploadItem extends UploadItem<TransactionResult> {
  BundleTransactionUploadItem(
      {required int size, required TransactionResult data})
      : super(size: size, data: data);
}

abstract class UploadTask<T> {
  abstract final String id;
  abstract final UploadItem? uploadItem;
  abstract final List<ARFSUploadMetadata>? content;
  abstract double progress;
  abstract bool isProgressAvailable;
  abstract UploadStatus status;

  UploadTask copyWith({
    UploadItem? uploadItem,
    double? progressInPercentage,
    bool? isProgressAvailable,
    UploadStatus? status,
    String? id,
    List<ARFSUploadMetadata>? content,
  });
}

class ARFSUploadTask implements UploadTask<ARFSUploadMetadata> {
  @override
  final UploadItem? uploadItem;

  @override
  final List<ARFSUploadMetadata>? content;

  @override
  double progress = 0;

  @override
  final String id;

  @override
  bool isProgressAvailable = true;

  ARFSUploadTask({
    this.uploadItem,
    this.isProgressAvailable = true,
    this.status = UploadStatus.notStarted,
    this.content,
    String? id,
  }) : id = id ?? const Uuid().v4();

  @override
  UploadStatus status;

  @override
  ARFSUploadTask copyWith({
    UploadItem? uploadItem,
    double? progressInPercentage,
    bool? isProgressAvailable,
    UploadStatus? status,
    String? id,
    List<ARFSUploadMetadata>? content,
  }) {
    return ARFSUploadTask(
      uploadItem: uploadItem ?? this.uploadItem,
      content: content ?? this.content,
      id: id ?? this.id,
      isProgressAvailable: isProgressAvailable ?? this.isProgressAvailable,
      status: status ?? this.status,
    );
  }
}

abstract class UploadController {
  abstract final Map<String, UploadTask> tasks;

  Future<void> close();
  void cancel();
  void onCancel();
  void onDone(Function(List<UploadTask> tasks) callback);
  void onError(Function(List<UploadTask> tasks) callback);
  void updateProgress({UploadTask? task});
  void onProgressChange(Function(UploadProgress progress) callback);

  factory UploadController(
    StreamController<UploadProgress> progressStream,
    StreamedUpload streamedUpload,
  ) {
    return _UploadController(
      progressStream: progressStream,
      streamedUpload: streamedUpload,
    );
  }
}

class _UploadController implements UploadController {
  final StreamController<UploadProgress> _progressStream;
  final StreamedUpload _streamedUpload;

  _UploadController({
    required StreamController<UploadProgress> progressStream,
    required StreamedUpload streamedUpload,
  })  : _progressStream = progressStream,
        _streamedUpload = streamedUpload {
    init();
  }

  bool _isCanceled = false;
  bool get isCanceled => _isCanceled;
  DateTime? _start;

  void init() {
    _isCanceled = false;
    late StreamSubscription subscription;

    subscription =
        _progressStream.stream.debounceTime(Duration(milliseconds: 100)).listen(
      (event) async {
        _start ??= DateTime.now();

        _onProgressChange!(event);

        if (_uploadProgress.progressInPercentage == 1) {
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
    // TODO: it's uploading closing the progress stream. We need to cancel the upload
    _isCanceled = true;
    _progressStream.close();
  }

  @override
  void onCancel() {
    // TODO: implement onCancel
  }

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

      // TODO: Check how to improve this
      final taskList = tasks.values.toList();

      // TODO: Check how to improve this
      _uploadProgress = _uploadProgress.copyWith(
        task: taskList,
        progressInPercentage: calculateTotalProgress(taskList),
        totalSize: totalSize(taskList),
        totalUploaded: totalUploaded(taskList),
        startTime: _start,
      );

      _progressStream.add(_uploadProgress);
    }

    return;
  }

  UploadProgress _uploadProgress = UploadProgress.notStarted();

  @override
  void onError(Function(List<UploadTask> tasks) callback) {}

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

  // TODO: CALCULATE BASED ON TOTAL SIZE NOT ONLY ON THE NUMBER OF TASKS
  double calculateTotalProgress(List<UploadTask> tasks) {
    return tasks
            .map((e) => e.progress)
            .reduce((value, element) => value + element) /
        tasks.length;
  }

  int totalUploaded(List<UploadTask> tasks) {
    int totalUploaded = 0;

    for (var task in tasks) {
      if (task.uploadItem != null) {
        totalUploaded += (task.progress * task.uploadItem!.size).toInt();
      }
    }

    return totalUploaded;
  }

  int totalSize(List<UploadTask> tasks) {
    int totalSize = 0;

    for (var task in tasks) {
      if (task.uploadItem != null) {
        totalSize += task.uploadItem!.size;
      }
    }

    return totalSize;
  }

  /// It is just an experimentation. It is not used yet, but it will be used in the future.
  /// When this implementation is stable, we must add this method on its interface class: `UploadController`.
  Future<void> retryFailedTasks(Wallet wallet) async {
    final failedTasks =
        tasks.values.where((e) => e.status == UploadStatus.failed).toList();

    if (failedTasks.isEmpty) {
      return Future.value();
    }

    for (var task in failedTasks) {
      task.copyWith(status: UploadStatus.notStarted);

      updateProgress(task: task);

      _streamedUpload.send(task, wallet, this);
    }
  }

  /// It is just an experimentation. It is not used yet, but it will be used in the future.
  /// When this implementation is stable, we must add this method on its interface class: `UploadController`.
  Future<void> retryTask(UploadTask task, Wallet wallet) async {
    task.copyWith(status: UploadStatus.notStarted);

    updateProgress(task: task);

    _streamedUpload.send(task, wallet, this);
  }
}

enum UploadStatus {
  /// The upload is not started yet
  notStarted,

  /// The upload is in progress
  inProgress,

  /// The upload is being bundled
  bundling,

  /// The upload is being encrypted
  encryting,

  /// The upload is paused
  paused,

  /// The upload is prepartion is done: the bundle is ready to be uploaded
  preparationDone,

  /// The upload is complete
  complete,

  /// The upload has failed
  failed,
}

class UploadProgress {
  /// The progress in percentage from 0 to 1
  final double progressInPercentage;
  final int totalSize;
  final int totalUploaded;
  final List<UploadTask> task;

  DateTime? startTime;

  UploadProgress({
    required this.progressInPercentage,
    required this.totalSize,
    required this.task,
    required this.totalUploaded,
    this.startTime,
  });

  factory UploadProgress.notStarted() {
    return UploadProgress(
      progressInPercentage: 0,
      totalSize: 0,
      task: [],
      totalUploaded: 0,
    );
  }

  UploadProgress copyWith({
    double? progressInPercentage,
    int? totalSize,
    List<UploadTask>? task,
    int? totalUploaded,
    DateTime? startTime,
  }) {
    return UploadProgress(
      startTime: startTime ?? this.startTime,
      progressInPercentage: progressInPercentage ?? this.progressInPercentage,
      totalSize: totalSize ?? this.totalSize,
      task: task ?? this.task,
      totalUploaded: totalUploaded ?? this.totalUploaded,
    );
  }

  int getNumberOfItems() {
    if (task.isEmpty) {
      return 0;
    }

    return task.map((e) {
      if (e.content == null) {
        return 0;
      }

      return e.content!.length;
    }).reduce((value, element) => value + element);
  }

  int tasksContentLength() {
    int totalUploaded = 0;

    for (var t in task) {
      if (t.content != null) {
        totalUploaded += t.content!.length;
      }
    }

    return totalUploaded;
  }

  int tasksContentCompleted() {
    int totalUploaded = 0;

    for (var t in task) {
      if (t.content != null) {
        if (t.status == UploadStatus.complete) {
          totalUploaded += t.content!.length;
        }
      }
    }

    return totalUploaded;
  }

  double calculateUploadSpeed() {
    if (startTime == null) return 0.0;

    final elapsedTime = DateTime.now().difference(startTime!).inSeconds;

    if (elapsedTime == 0) return 0.0;

    return (totalUploaded / elapsedTime).toDouble(); // Assuming speed in MB/s
  }
}

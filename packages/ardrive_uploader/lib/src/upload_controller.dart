import 'dart:async';

import 'package:ardrive_uploader/src/exceptions.dart';
import 'package:ardrive_uploader/src/upload_dispatcher.dart';
import 'package:ardrive_uploader/src/utils/logger.dart';
import 'package:arweave/arweave.dart';
import 'package:rxdart/rxdart.dart';

import '../ardrive_uploader.dart';

abstract class UploadController {
  abstract final Map<String, UploadTask> tasks;

  Future<void> close();
  Future<void> cancel();
  void onCancel(Function(List<UploadTask> tasks) callback);
  void onDone(Function(List<UploadTask> tasks) callback);
  void onError(Function(List<UploadTask> tasks) callback);
  void updateProgress({UploadTask? task});
  void onProgressChange(Function(UploadProgress progress) callback);
  void onCompleteTask(Function(UploadTask tasks) callback);
  void sendTasks(Wallet wallet);

  List<UploadTask> get notCompletedTasks;

  /// onTaskCompleted is a callback that is called when a task is completed.
  /// it pass true if the task is completed successfully, otherwise it pass false.
  void sendTask(
    UploadTask task,
    Wallet wallet, {
    Function(bool)? onTaskCompleted,
  });
  void addTask(UploadTask task);
  void onFailedTask(Function(UploadTask task) callback);
  Future<void> retryFailedTasks(Wallet wallet);

  factory UploadController(
    StreamController<UploadProgress> progressStream,
    UploadDispatcher uploadDispatcher, {
    int numOfWorkers = 5,
    int maxTasksPerWorker = 5,
  }) {
    return _UploadController(
      progressStream: progressStream,
      uploadSender: uploadDispatcher,
      numOfWorkers: numOfWorkers,
      maxTasksPerWorker: maxTasksPerWorker,
    );
  }
}

class _UploadController implements UploadController {
  StreamController<UploadProgress> _progressStream;
  final int _numOfWorkers;
  final int _maxTasksPerWorker;
  final UploadDispatcher _uploadDispatcher;

  _UploadController({
    required StreamController<UploadProgress> progressStream,
    required UploadDispatcher uploadSender,
    int numOfWorkers = 2,
    int maxTasksPerWorker = 5,
  })  : _uploadDispatcher = uploadSender,
        _numOfWorkers = numOfWorkers,
        _maxTasksPerWorker = maxTasksPerWorker,
        _progressStream = progressStream {
    init();
  }

  bool _isCanceled = false;
  bool get isCanceled => _isCanceled;
  DateTime? _start;

  WorkerPool? workerPool;

  @override
  final Map<String, UploadTask> tasks = {};
  final Map<String, UploadTask> _completedTasks = {};
  final Map<String, UploadTask> _failedTasks = {};
  final Map<String, UploadTask> _canceledTasks = {};
  final Map<String, UploadTask> _inProgressTasks = {};

  @override
  List<UploadTask> get notCompletedTasks =>
      tasks.values.where((e) => e.status != UploadStatus.complete).toList();

  int _totalSize = 0;
  int _numberOfItems = 0;
  double _totalProgress = 0;
  int _totalUploaded = 0;
  int _totalUploadedItems = 0;

  final UploadProgress _uploadProgress = UploadProgress.notStarted();

  void init() {
    _isCanceled = false;
    late StreamSubscription subscription;

    subscription =
        _progressStream.stream.debounceTime(Duration(milliseconds: 100)).listen(
      (event) async {
        if (_isCanceled) {
          return;
        }

        _onProgressChange!(event);

        final finishedTasksLength =
            _failedTasks.length + _completedTasks.length;

        if (finishedTasksLength == tasks.length) {
          await close();
          return;
        }
      },
      onDone: () {
        if (_failedTasks.isNotEmpty) {
          _onError(_failedTasks.values.toList());
          return;
        }
        _onDone(tasks.values.toList());
        subscription.cancel();
      },
      onError: (err) {
        logger.d('Error on UploadController: $err');
        subscription.cancel();
      },
    );
  }

  @override
  void updateProgress({UploadTask? task}) async {
    if (_progressStream.isClosed || task == null) return;

    if (_start == null && task.status == UploadStatus.inProgress) {
      _start = DateTime.now();
    }

    final taskId = task.id;
    final existingTask = tasks[taskId];
    final uploadItem = task.uploadItem;

    if (task.progress == 1 && task.status == UploadStatus.inProgress) {
      task = task.copyWith(status: UploadStatus.finalizing);
    }

    tasks[taskId] = task;
    _updateTaskStatus(task, taskId);
    _updateTotalSize(task, uploadItem, existingTask);
    _updateProgress(task, uploadItem, existingTask);

    _progressStream.add(_generateUploadProgress());
  }

  @override
  void onError(Function(List<UploadTask> tasks) callback) {
    _onError = callback;
  }

  @override
  void onProgressChange(Function(UploadProgress progress) callback) {
    _onProgressChange = callback;
  }

  @override
  void sendTasks(
    Wallet wallet,
  ) {
    if (tasks.isEmpty) {
      throw Exception('No tasks to send');
    }

    // creates a worker pool and initializes it with the tasks
    workerPool = WorkerPool(
      numWorkers: _numOfWorkers,
      maxTasksPerWorker: _maxTasksPerWorker,
      taskQueue: tasks.values
          .where((element) => element.status == UploadStatus.notStarted)
          .toList(),
      onWorkerError: (e) {
        /// Handles any uncaught error on the worker. It is not supposed to happen as
        /// the `_uploadDispatcher` should handle all the errors and return an `UploadResult`
        logger.d('Error on UploadWorker. Task: ${e.toString()}');

        _handleError(task: tasks[e.id]!, exception: e);
      },
      upload: (task) async {
        final uploadResult = await _uploadDispatcher.send(
          task: task,
          wallet: wallet,
          controller: this,
          verifyCancel: () => _isCanceled,
        );

        if (!uploadResult.success) {
          _handleError(task: task, exception: uploadResult.error);
        }
      },
    );
  }

  @override
  void addTask(UploadTask task) {
    if (task.content != null) {
      _numberOfItems += task.content!.length;

      if (task is FileUploadTask) {
        for (var content in task.content!) {
          final fileMetadata = content as ARFSFileUploadMetadata;
          _totalSize += fileMetadata.size;
        }
      }
    }

    tasks[task.id] = task;
  }

  @override
  void sendTask(
    UploadTask task,
    Wallet wallet, {
    Function(bool)? onTaskCompleted,
  }) {
    final worker = UploadWorker(
      onError: (task, e) {
        /// Handles any uncaught error on the worker. It is not supposed to happen as
        /// the `_uploadDispatcher` should handle all the errors and return an `UploadResult`
        logger.d('Error on UploadWorker. Task: ${task.toString()}');

        _handleError(task: task, exception: e);
      },
      upload: (task) async {
        final uploadResult = await _uploadDispatcher.send(
          task: task,
          wallet: wallet,
          controller: this,
          verifyCancel: () => _isCanceled,
        );

        if (!uploadResult.success) {
          _handleError(task: task, exception: uploadResult.error);
        }
      },
      maxTasks: 1,
      task: task,
      onTaskCompleted: (task) {
        logger.d('Task completed with status: ${task.status}');
        final updatedTask = tasks[task.id]!;
        onTaskCompleted?.call(updatedTask.status == UploadStatus.complete);
      },
    );

    worker.addTask(task);
  }

  @override
  void onCancel(Function(List<UploadTask> tasks) callback) {
    _onCancel = callback;
  }

  @override
  void onCompleteTask(Function(UploadTask tasks) callback) {
    _onCompleteTask = callback;
  }

  @override
  void onDone(Function(List<UploadTask> tasks) callback) {
    _onDone = callback;
  }

  /// It is just an experimentation. It is not used yet, but it will be used in the future.
  /// When this implementation is stable, we must add this method on its interface class: `UploadController`.
  @override
  Future<void> retryFailedTasks(Wallet wallet) async {
    _progressStream.close();
    _progressStream = StreamController.broadcast();

    /// Clean up the tasks
    tasks.clear();
    _completedTasks.clear();
    _canceledTasks.clear();
    _inProgressTasks.clear();

    _resetUploadProgress();

    _progressStream.add(UploadProgress.notStarted());

    /// Add the failed tasks back to the tasks list as not started
    for (var task in _failedTasks.values) {
      if (task is FileUploadTask) {
        addTask(
          task.copyWith(
            status: UploadStatus.notStarted,
            progress: 0,
            cancelToken: null,
            metadata: task.metadata,
          ),
        );
      } else if (task is FolderUploadTask) {
        addTask(
          task.copyWith(
            status: UploadStatus.notStarted,
            progress: 0,
            cancelToken: null,
            folders: task.folders,
          ),
        );
      }
    }

    logger.d('Retrying failed tasks.');

    _failedTasks.clear();

    init();

    /// All folders goes in a single bundle. We are safe to send all the folders at once.
    final folderTasks = tasks.values.whereType<FolderUploadTask>();

    final containsFolder = folderTasks.isNotEmpty;

    /// If the tasks contains a folder, we must send the folder first
    if (containsFolder) {
      sendTask(
        folderTasks.first,
        wallet,
        onTaskCompleted: (success) {
          if (success) {
            sendTasks(wallet);
          } else {
            for (var task in tasks.values) {
              task = task.copyWith(status: UploadStatus.failed);
              updateProgress(task: task);
            }
          }
        },
      );
    } else {
      sendTasks(wallet);
    }
  }

  Future<void> retryTask(UploadTask task, Wallet wallet) async {
    task.copyWith(status: UploadStatus.notStarted);

    updateProgress(task: task);

    _uploadDispatcher.send(
      task: task,
      wallet: wallet,
      controller: this,
      verifyCancel: () => _isCanceled,
    );
  }

  @override
  Future<void> close() async {
    if (!_progressStream.isClosed) {
      await _progressStream.close();
    }
  }

  @override
  Future<void> cancel() async {
    if (_isCanceled) {
      return;
    }

    workerPool?.cancel();
    _isCanceled = true;

    final cancelableTask = tasks.values
        .where((e) =>
            e.status != UploadStatus.assigningUndername &&
            e.status != UploadStatus.complete &&
            e.status != UploadStatus.failed)
        .toList();

    final cancelTasksFuture = cancelableTask.map(
      (task) async {
        await task.cancelToken?.cancel();

        task = task.copyWith(status: UploadStatus.canceled);

        _canceledTasks.putIfAbsent(task.id, () => task);

        updateProgress(task: task);
      },
    );

    await Future.wait(cancelTasksFuture);

    _onCancel(_canceledTasks.values.toList());

    _progressStream.close();
  }

  int totalSize() {
    return _totalSize;
  }

  /// Set the status of the task to failed and update the progress
  ///
  /// Calls the callback to the caller that the task has failed
  void _handleError({
    required UploadTask task,
    required Object? exception,
  }) {
    if (_isCanceled) return;

    final updatedTask =
        tasks[task.id]!.copyWith(error: exception, status: UploadStatus.failed);

    updateProgress(task: updatedTask);

    if (exception is UploadStrategyException &&
        exception.error is UnderFundException) {
      _isCanceled = true;

      final cancelableTask = tasks.values
          .where((e) =>
              e.status != UploadStatus.complete &&
              e.status != UploadStatus.failed)
          .toList();

      final cancelTasksFutureAsFailedUploads = cancelableTask.map(
        (task) async {
          await task.cancelToken?.cancel();

          task = task.copyWith(status: UploadStatus.failed);

          _failedTasks.putIfAbsent(task.id, () => task);

          updateProgress(task: task);
        },
      );

      Future.wait(cancelTasksFutureAsFailedUploads).then((_) {
        _onError(_failedTasks.values.toList());
      });

      return;
    }

    /// Callback to the caller that the task has failed
    _onFailedTask(updatedTask);
  }

  void _resetUploadProgress() {
    _numberOfItems = 0;
    _totalProgress = 0;
    _totalUploaded = 0;
    _totalUploadedItems = 0;
    _totalSize = 0;
    _start = null;
  }

  @override
  void onFailedTask(Function(UploadTask task) callback) {
    _onFailedTask = callback;
  }

  void Function(UploadProgress progress)? _onProgressChange = (progress) {};

  void Function(List<UploadTask> tasks) _onDone = (List<UploadTask> tasks) {};

  void Function(List<UploadTask> tasks) _onCancel = (List<UploadTask> tasks) {};

  void Function(List<UploadTask> tasks) _onError = (List<UploadTask> tasks) {};

  void Function(UploadTask task) _onCompleteTask = (UploadTask tasks) {};

  void Function(UploadTask task) _onFailedTask = (UploadTask tasks) {};

  void _updateTaskStatus(UploadTask task, String taskId) {
    switch (task.status) {
      case UploadStatus.complete:
        if (_completedTasks[taskId] == null) {
          _onCompleteTask(task);
        }
        _completedTasks[taskId] = task;
        _totalUploadedItems += task.content!.length;
        _inProgressTasks.remove(taskId);
        break;
      case UploadStatus.failed:
        _failedTasks[taskId] = task;
        _inProgressTasks.remove(taskId);
        break;
      case UploadStatus.inProgress:
        _inProgressTasks[taskId] = task;
        break;
      default:
        _inProgressTasks.remove(taskId);
        break;
    }
  }

  void _updateProgress(
      UploadTask task, UploadItem? uploadItem, UploadTask? existingTask) {
    if (existingTask?.uploadItem != null && uploadItem != null) {
      final diff = task.progress - existingTask!.progress;
      if (diff > 0) {
        _totalUploaded += (diff * uploadItem.size).toInt();
        _totalProgress += diff;
      }
    }
  }

  Future<void> _updateTotalSize(
      UploadTask task, UploadItem? uploadItem, UploadTask? existingTask) async {
    if (existingTask?.uploadItem == null && uploadItem != null) {
      if (task is FileUploadTask) {
        _totalSize -= await task.file.length;
      }
      _totalSize += uploadItem.size;
    }
  }

  UploadProgress _generateUploadProgress() {
    final progressInPercentage = _totalProgress / tasks.length;
    return _uploadProgress.copyWith(
      hasUploadInProgress: _inProgressTasks.isNotEmpty,
      tasks: tasks,
      progressInPercentage: progressInPercentage,
      totalSize: _totalSize,
      totalUploaded: _totalUploaded,
      startTime: _start,
      numberOfItems: _numberOfItems,
      numberOfUploadedItems: _totalUploadedItems,
    );
  }
}

enum UploadStatus {
  /// The upload is not started yet
  notStarted,

  /// The upload is in progress
  inProgress,

  /// The upload is being prepared
  creatingMetadata,

  /// The upload is being bundled
  creatingBundle,

  /// The upload is being encrypted
  encryting,

  /// The upload is paused
  paused,

  /// The upload is prepartion is done: the bundle is ready to be uploaded
  preparationDone,

  // The upload is being finalized
  finalizing,

  /// The upload is complete
  complete,

  /// The upload has failed
  failed,

  /// uploading thumbnail
  uploadingThumbnail,

  /// The upload has been canceled
  canceled,

  /// Assiging ArNS Name
  assigningUndername,
}

class UploadProgress {
  /// The progress in percentage from 0 to 1
  final double progressInPercentage;
  final int totalSize;
  final int totalUploaded;
  final Map<String, UploadTask> tasks;
  final int numberOfItems;
  final int numberOfUploadedItems;

  final bool hasUploadInProgress;

  DateTime? startTime;

  UploadProgress({
    required this.progressInPercentage,
    required this.totalSize,
    required this.tasks,
    required this.totalUploaded,
    required this.numberOfItems,
    required this.numberOfUploadedItems,
    required this.hasUploadInProgress,
    this.startTime,
  });

  factory UploadProgress.notStarted() {
    return UploadProgress(
      progressInPercentage: 0,
      totalSize: 0,
      tasks: {},
      totalUploaded: 0,
      numberOfItems: 0,
      numberOfUploadedItems: 0,
      hasUploadInProgress: false,
    );
  }

  UploadProgress copyWith({
    double? progressInPercentage,
    int? totalSize,
    Map<String, UploadTask>? tasks,
    int? totalUploaded,
    DateTime? startTime,
    int? numberOfItems,
    int? numberOfUploadedItems,
    bool? hasUploadInProgress,
  }) {
    return UploadProgress(
      hasUploadInProgress: hasUploadInProgress ?? this.hasUploadInProgress,
      numberOfUploadedItems:
          numberOfUploadedItems ?? this.numberOfUploadedItems,
      startTime: startTime ?? this.startTime,
      progressInPercentage: progressInPercentage ?? this.progressInPercentage,
      totalSize: totalSize ?? this.totalSize,
      tasks: tasks ?? this.tasks,
      totalUploaded: totalUploaded ?? this.totalUploaded,
      numberOfItems: numberOfItems ?? this.numberOfItems,
    );
  }

  double calculateUploadSpeed() {
    if (startTime == null) return 0.0;

    final elapsedTime = DateTime.now().difference(startTime!).inSeconds;

    if (elapsedTime == 0) return 0.0;

    return (totalUploaded / elapsedTime).toDouble(); // Assuming speed in MB/s
  }
}

class UploadWorker {
  final Function(UploadTask) onTaskCompleted;
  final Function(UploadTask) upload;
  final Function(UploadTask, Object e) onError;
  final int maxTasks;
  final UploadTask? task;

  List<Future<void>> taskFutures = [];

  UploadWorker({
    required this.onTaskCompleted,
    this.maxTasks = 5,
    required this.upload,
    required this.onError,
    this.task,
  });

  void addTask(UploadTask task) {
    if (taskFutures.length < maxTasks) {
      final future = _upload(task);
      taskFutures.add(future);

      future.then((_) {
        taskFutures.remove(future);
        onTaskCompleted(task);
      });
    }
  }

  Future<void> _upload(UploadTask task) async {
    try {
      await upload(task);

      return;
    } catch (e) {
      logger.d('catched error on upload worker: $e');
      onError(task, e);
    }
  }
}

class WorkerPool {
  final int numWorkers;
  final int maxTasksPerWorker;
  final List<UploadTask> taskQueue;
  late List<UploadWorker> workers;
  final Function(UploadTask) upload;
  final Function(UploadTask) onWorkerError;

  WorkerPool({
    required this.numWorkers,
    required this.maxTasksPerWorker,
    required this.taskQueue,
    required this.upload,
    required this.onWorkerError,
  }) {
    _setWorkerCallbacks();
    _initializeWorkers();
  }

  void _setWorkerCallbacks() {
    workers = List<UploadWorker>.generate(numWorkers, (i) {
      final worker = UploadWorker(
        upload: upload,
        onError: (task, exception) => onWorkerError(task),
        maxTasks: maxTasksPerWorker,
        onTaskCompleted: (task) {
          if (_isCanceled) {
            return;
          }

          _assignNextTask(i);
        },
      );
      return worker;
    });
  }

  void _initializeWorkers() {
    for (var i = 0; i < numWorkers; i++) {
      logger.d('Initializing worker with index $i');

      for (var j = 0; j < maxTasksPerWorker; j++) {
        logger.d('Assigning task $j to worker with index $i');

        _assignNextTask(i);
      }
    }
  }

  void _assignNextTask(int workerIndex) {
    if (taskQueue.isNotEmpty) {
      final nextTask = taskQueue.removeAt(0);
      workers[workerIndex].addTask(nextTask);
    }
  }

  void cancel() {
    _isCanceled = true;
  }

  bool get isCanceled => _isCanceled;

  bool _isCanceled = false;
}

abstract class UploadItem<T> {
  final int size;
  final T data;
  final Map<String, String>? headers;

  UploadItem({
    required this.size,
    required this.data,
    this.headers,
  });
}

class DataItemUploadItem extends UploadItem<DataItemResult> {
  DataItemUploadItem({required super.size, required super.data, super.headers});

  @override
  String toString() {
    return 'DataItemUploadItem(id: ${data.id}, size: $size, headers: $headers)';
  }
}

class TransactionUploadItem extends UploadItem<TransactionResult> {
  TransactionUploadItem({required super.size, required super.data});

  @override
  String toString() {
    return 'TransactionUploadItem(id: ${data.id}, size: $size)';
  }
}

class UploadTaskCancelToken {
  final Function() cancel;

  UploadTaskCancelToken({
    required this.cancel,
  });
}

class UploadResult {
  final bool success;
  final Object? error;

  UploadResult({
    required this.success,
    this.error,
  });
}

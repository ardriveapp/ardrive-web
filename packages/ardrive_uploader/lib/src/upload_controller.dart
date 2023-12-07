import 'dart:async';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/src/data_bundler.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';

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
  void sendTask(UploadTask task, Wallet wallet, {Function()? onTaskCompleted});
  void addTask(UploadTask task);
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
        debugPrint('Error on UploadController: $err');
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

    _updateTaskStatus(task, taskId);
    _updateTotalSize(task, uploadItem, existingTask);
    _updateProgress(task, uploadItem, existingTask);

    tasks[taskId] = task;
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
        debugPrint('Error on UploadWorker. Task: ${e.toString()}');
        final updatedTask = tasks[e.id]!;

        updateProgress(task: updatedTask.copyWith(status: UploadStatus.failed));
      },
      upload: (task) async {
        final uploadResult = await _uploadDispatcher.send(
          task: task,
          wallet: wallet,
          controller: this,
          verifyCancel: () => _isCanceled,
        );

        if (!uploadResult.success) {
          final updatedTask = tasks[task.id]!;

          updateProgress(
              task: updatedTask.copyWith(status: UploadStatus.failed));
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
    Function()? onTaskCompleted,
  }) {
    final worker = UploadWorker(
      onError: (task, e) {
        debugPrint('Error on UploadWorker. Task: ${e.toString()}');
        final updatedTask = tasks[task.id]!;
        updateProgress(task: updatedTask.copyWith(status: UploadStatus.failed));
      },
      upload: (task) async {
        final uploadResult = await _uploadDispatcher.send(
          task: task,
          wallet: wallet,
          controller: this,
          verifyCancel: () => _isCanceled,
        );

        if (!uploadResult.success) {
          final updatedTask = tasks[task.id]!;

          updateProgress(
              task: updatedTask.copyWith(status: UploadStatus.failed));
        }
      },
      maxTasks: 1,
      task: task,
      onTaskCompleted: () {
        onTaskCompleted?.call();
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

    final failedTasks =
        tasks.values.where((e) => e.status == UploadStatus.failed).toList();

    if (failedTasks.isEmpty) {
      return Future.value();
    }

    _resetUploadProgress();

    _failedTasks.clear();
    _completedTasks.clear();
    tasks.clear();

    for (var task in failedTasks) {
      addTask(
        task.copyWith(
          status: UploadStatus.notStarted,
          progress: 0,
          cancelToken: null,
        ),
      );
    }

    init();

    // creates a worker pool and initializes it with the tasks
    WorkerPool(
      numWorkers: _numOfWorkers,
      maxTasksPerWorker: _maxTasksPerWorker,
      taskQueue: tasks.values
          .where((element) => element.status == UploadStatus.notStarted)
          .toList(),
      onWorkerError: (e) {
        final updatedTask = tasks[e.id]!;

        updateProgress(task: updatedTask.copyWith(status: UploadStatus.failed));

        debugPrint('Unknown error on UploadWorker. Task: ${e.toString()}');
      },
      upload: (task) async {
        final uploadResult = await _uploadDispatcher.send(
          task: task,
          wallet: wallet,
          controller: this,
          verifyCancel: () => _isCanceled,
        );

        if (!uploadResult.success) {
          final updatedTask = tasks[task.id]!;

          updateProgress(
              task: updatedTask.copyWith(status: UploadStatus.failed));
        }
      },
    );
  }

  /// It is just an experimentation. It is not used yet, but it will be used in the future.
  /// When this implementation is stable, we must add this method on its interface class: `UploadController`.
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
    await _progressStream.close();
  }

  @override
  Future<void> cancel() async {
    workerPool?.cancel();
    _isCanceled = true;

    final cancelableTask = tasks.values
        .where((e) =>
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

  void _resetUploadProgress() {
    _numberOfItems = 0;
    _totalProgress = 0;
    _totalUploaded = 0;
    _totalUploadedItems = 0;
    _start = null;
  }

  void Function(UploadProgress progress)? _onProgressChange = (progress) {};

  void Function(List<UploadTask> tasks) _onDone = (List<UploadTask> tasks) {
    print('Upload Finished');
  };

  void Function(List<UploadTask> tasks) _onCancel = (List<UploadTask> tasks) {
    print('Upload Canceled');
  };

  void Function(List<UploadTask> tasks) _onError = (List<UploadTask> tasks) {
    print('Upload Error');
  };

  void Function(UploadTask task) _onCompleteTask = (UploadTask tasks) {
    print('Upload Canceled');
  };

  void _updateTaskStatus(UploadTask task, String taskId) {
    switch (task.status) {
      case UploadStatus.complete:
        if (_completedTasks[taskId] == null) {
          _onCompleteTask(task);
        }
        _completedTasks[taskId] = task;
        _totalUploadedItems += task.content!.length;
        break;
      case UploadStatus.failed:
        _failedTasks[taskId] = task;
        break;
      default:
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
      task: tasks,
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

  /// The upload is complete
  complete,

  /// The upload has failed
  failed,

  /// The upload has been canceled
  canceled,
}

class UploadProgress {
  /// The progress in percentage from 0 to 1
  final double progressInPercentage;
  final int totalSize;
  final int totalUploaded;
  final Map<String, UploadTask> task;
  final int numberOfItems;
  final int numberOfUploadedItems;

  DateTime? startTime;

  UploadProgress({
    required this.progressInPercentage,
    required this.totalSize,
    required this.task,
    required this.totalUploaded,
    required this.numberOfItems,
    required this.numberOfUploadedItems,
    this.startTime,
  });

  factory UploadProgress.notStarted() {
    return UploadProgress(
      progressInPercentage: 0,
      totalSize: 0,
      task: {},
      totalUploaded: 0,
      numberOfItems: 0,
      numberOfUploadedItems: 0,
    );
  }

  UploadProgress copyWith({
    double? progressInPercentage,
    int? totalSize,
    Map<String, UploadTask>? task,
    int? totalUploaded,
    DateTime? startTime,
    int? numberOfItems,
    int? numberOfUploadedItems,
  }) {
    return UploadProgress(
      numberOfUploadedItems:
          numberOfUploadedItems ?? this.numberOfUploadedItems,
      startTime: startTime ?? this.startTime,
      progressInPercentage: progressInPercentage ?? this.progressInPercentage,
      totalSize: totalSize ?? this.totalSize,
      task: task ?? this.task,
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
  final Function() onTaskCompleted;
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
        onTaskCompleted();
      });
    }
  }

  Future<void> _upload(UploadTask task) async {
    try {
      await upload(task);

      return;
    } catch (e) {
      debugPrint('catched error on upload worker: $e');
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
        onTaskCompleted: () {
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
      debugPrint('Initializing worker with index $i');

      for (var j = 0; j < maxTasksPerWorker; j++) {
        debugPrint('Assigning task $j to worker with index $i');

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

  UploadItem({required this.size, required this.data});
}

class DataItemUploadItem extends UploadItem<DataItemResult> {
  DataItemUploadItem({required int size, required DataItemResult data})
      : super(size: size, data: data);
}

class TransactionUploadItem extends UploadItem<TransactionResult> {
  TransactionUploadItem({required int size, required TransactionResult data})
      : super(size: size, data: data);
}

class FolderUploadTask implements UploadTask<ARFSUploadMetadata> {
  final List<(ARFSFolderUploadMetatadata, IOEntity)> folders;

  @override
  final UploadItem? uploadItem;

  @override
  final List<ARFSUploadMetadata>? content;

  @override
  final double progress;

  @override
  final String id;

  @override
  bool isProgressAvailable = true;

  @override
  UploadTaskCancelToken? cancelToken;

  @override
  final UploadType type;

  FolderUploadTask({
    required this.folders,
    this.uploadItem,
    this.isProgressAvailable = true,
    this.status = UploadStatus.notStarted,
    this.content,
    this.encryptionKey,
    this.progress = 0,
    this.cancelToken,
    String? id,
    required this.type,
  }) : id = id ?? const Uuid().v4();

  @override
  UploadStatus status;

  @override
  FolderUploadTask copyWith({
    UploadItem? uploadItem,
    double? progress,
    bool? isProgressAvailable,
    UploadStatus? status,
    String? id,
    List<ARFSUploadMetadata>? content,
    SecretKey? encryptionKey,
    List<(ARFSFolderUploadMetatadata, IOEntity)>? folders,
    UploadTaskCancelToken? cancelToken,
    UploadType? type,
  }) {
    return FolderUploadTask(
      cancelToken: cancelToken ?? this.cancelToken,
      folders: folders ?? this.folders,
      uploadItem: uploadItem ?? this.uploadItem,
      content: content ?? this.content,
      id: id ?? this.id,
      progress: progress ?? this.progress,
      isProgressAvailable: isProgressAvailable ?? this.isProgressAvailable,
      status: status ?? this.status,
      type: type ?? this.type,
    );
  }

  @override
  final SecretKey? encryptionKey;
}

class FileUploadTask extends UploadTask {
  final IOFile file;

  final ARFSFileUploadMetadata metadata;

  @override
  final UploadItem? uploadItem;

  @override
  final List<ARFSUploadMetadata>? content;

  @override
  final double progress;

  @override
  final String id;

  @override
  bool isProgressAvailable = true;

  bool metadataUploaded;

  @override
  UploadTaskCancelToken? cancelToken;

  FileUploadTask({
    this.uploadItem,
    this.isProgressAvailable = true,
    this.status = UploadStatus.notStarted,
    this.content,
    String? id,
    required this.file,
    required this.metadata,
    this.encryptionKey,
    this.cancelToken,
    this.progress = 0,
    required this.type,
    this.metadataUploaded = false,
  }) : id = id ?? const Uuid().v4();

  @override
  UploadStatus status;

  @override
  FileUploadTask copyWith({
    UploadItem? uploadItem,
    double? progress,
    bool? isProgressAvailable,
    UploadStatus? status,
    String? id,
    ARFSFileUploadMetadata? metadata,
    List<ARFSUploadMetadata>? content,
    SecretKey? encryptionKey,
    UploadTaskCancelToken? cancelToken,
    UploadType? type,
    bool? metadataUploaded,
  }) {
    return FileUploadTask(
      cancelToken: cancelToken ?? this.cancelToken,
      encryptionKey: encryptionKey ?? this.encryptionKey,
      metadata: metadata ?? this.metadata,
      uploadItem: uploadItem ?? this.uploadItem,
      content: content ?? this.content,
      id: id ?? this.id,
      isProgressAvailable: isProgressAvailable ?? this.isProgressAvailable,
      status: status ?? this.status,
      file: file,
      progress: progress ?? this.progress,
      type: type ?? this.type,
      metadataUploaded: metadataUploaded ?? this.metadataUploaded,
    );
  }

  @override
  final SecretKey? encryptionKey;

  @override
  UploadType type;
}

abstract class UploadTask<T> {
  abstract final String id;
  abstract final UploadItem? uploadItem;
  abstract final List<ARFSUploadMetadata>? content;
  abstract final double progress;
  abstract final bool isProgressAvailable;
  abstract final UploadStatus status;
  abstract final SecretKey? encryptionKey;
  abstract final UploadTaskCancelToken? cancelToken;
  abstract final UploadType type;

  UploadTask copyWith({
    UploadItem? uploadItem,
    double? progress,
    bool? isProgressAvailable,
    UploadStatus? status,
    String? id,
    List<ARFSUploadMetadata>? content,
    SecretKey? encryptionKey,
    UploadTaskCancelToken? cancelToken,
    UploadType? type,
  });
}

class UploadTaskCancelToken {
  final Function() cancel;

  UploadTaskCancelToken({
    required this.cancel,
  });
}

class UploadDispatcher {
  UploadFileStrategy _uploadFileStrategy;
  final UploadFolderStructureStrategy _uploadFolderStrategy;
  final DataBundler _dataBundler;

  UploadDispatcher({
    required UploadFileStrategy uploadStrategy,
    required DataBundler dataBundler,
    required UploadFolderStructureStrategy uploadFolderStrategy,
  })  : _dataBundler = dataBundler,
        _uploadFolderStrategy = uploadFolderStrategy,
        _uploadFileStrategy = uploadStrategy;

  Future<UploadResult> send({
    required UploadTask task,
    required Wallet wallet,
    required UploadController controller,
    required bool Function() verifyCancel,
  }) async {
    try {
      if (task is FileUploadTask) {
        final dataItems = await _dataBundler.createDataItemsForFile(
          file: task.file,
          metadata: task.metadata,
          wallet: wallet,
          onStartBundleCreation: () {
            controller.updateProgress(
              task: task.copyWith(
                status: UploadStatus.creatingBundle,
              ),
            );
          },
          onStartMetadataCreation: () {
            controller.updateProgress(
              task: task.copyWith(
                status: UploadStatus.creatingMetadata,
              ),
            );
          },
        );

        debugPrint(
            'Uploading task ${task.id} with strategy: ${_uploadFileStrategy.runtimeType}');

        await _uploadFileStrategy.upload(
          dataItems: dataItems,
          task: task,
          wallet: wallet,
          controller: controller,
          verifyCancel: verifyCancel,
        );
      } else if (task is FolderUploadTask) {
        await _uploadFolderStrategy.upload(
          task: task,
          wallet: wallet,
          controller: controller,
          verifyCancel: verifyCancel,
        );
      } else {
        throw Exception('Invalid task type');
      }

      return UploadResult(success: true);
    } catch (e) {
      debugPrint('Error on UploadDispatcher.send: $e');
      return UploadResult(
        success: false,
        error: e,
      );
    }
  }

  void setUploadFileStrategy(UploadFileStrategy strategy) {
    _uploadFileStrategy = strategy;
  }
}

class UploadResult {
  final bool success;
  final Object? error;

  UploadResult({
    required this.success,
    this.error,
  });
}

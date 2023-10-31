import 'dart:async';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/src/data_bundler.dart';
import 'package:ardrive_uploader/src/streamed_upload.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
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

class FolderUploadTask implements UploadTask<ARFSUploadMetadata> {
  final List<(ARFSFolderUploadMetatadata, IOEntity)> folders;

  @override
  final UploadItem? uploadItem;

  @override
  final StreamedUpload streamedUpload;

  @override
  final List<ARFSUploadMetadata>? content;

  @override
  final double progress;

  @override
  final String id;

  @override
  bool isProgressAvailable = true;

  FolderUploadTask({
    required this.folders,
    this.uploadItem,
    this.isProgressAvailable = true,
    this.status = UploadStatus.notStarted,
    this.content,
    this.encryptionKey,
    required this.streamedUpload,
    this.progress = 0,
    String? id,
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
    StreamedUpload? streamedUpload,
  }) {
    return FolderUploadTask(
      streamedUpload: streamedUpload ?? this.streamedUpload,
      folders: folders ?? this.folders,
      uploadItem: uploadItem ?? this.uploadItem,
      content: content ?? this.content,
      id: id ?? this.id,
      progress: progress ?? this.progress,
      isProgressAvailable: isProgressAvailable ?? this.isProgressAvailable,
      status: status ?? this.status,
    );
  }

  @override
  final SecretKey? encryptionKey;
}

class FileUploadTask extends UploadTask {
  final IOFile file;

  final ARFSFileUploadMetadata metadata;

  @override
  final StreamedUpload streamedUpload;

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

  FileUploadTask({
    this.uploadItem,
    this.isProgressAvailable = true,
    this.status = UploadStatus.notStarted,
    this.content,
    String? id,
    required this.file,
    required this.metadata,
    this.encryptionKey,
    required this.streamedUpload,
    this.progress = 0,
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
    StreamedUpload? streamedUpload,
  }) {
    return FileUploadTask(
      streamedUpload: streamedUpload ?? this.streamedUpload,
      encryptionKey: encryptionKey ?? this.encryptionKey,
      metadata: metadata ?? this.metadata,
      uploadItem: uploadItem ?? this.uploadItem,
      content: content ?? this.content,
      id: id ?? this.id,
      isProgressAvailable: isProgressAvailable ?? this.isProgressAvailable,
      status: status ?? this.status,
      file: file,
      progress: progress ?? this.progress,
    );
  }

  @override
  final SecretKey? encryptionKey;
}

abstract class UploadTask<T> {
  abstract final String id;
  abstract final UploadItem? uploadItem;
  abstract final List<ARFSUploadMetadata>? content;
  abstract final double progress;
  abstract final bool isProgressAvailable;
  abstract final UploadStatus status;
  abstract final SecretKey? encryptionKey;
  abstract final StreamedUpload streamedUpload;

  UploadTask copyWith({
    UploadItem? uploadItem,
    double? progress,
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
    this.encryptionKey,
    String? id,
  }) : id = id ?? const Uuid().v4();

  @override
  UploadStatus status;

  @override
  ARFSUploadTask copyWith({
    UploadItem? uploadItem,
    double? progress,
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

  @override
  final SecretKey? encryptionKey;

  @override
  // TODO: implement streamedUpload
  StreamedUpload get streamedUpload => throw UnimplementedError();
}

abstract class UploadController {
  abstract final Map<String, UploadTask> tasks;

  Future<void> close();
  Future<void> cancel();
  void onCancel(Function(List<UploadTask> tasks) callback);
  void onDone(Function(List<UploadTask> tasks) callback);
  void onError(Function(List<UploadTask> tasks) callback);
  void updateProgress({UploadTask? task});
  void onProgressChange(Function(UploadProgress progress) callback);
  void sendTasks(
    Wallet wallet,
  );
  void sendTask(UploadTask task, Wallet wallet, {Function()? onTaskCompleted});
  void addTask(UploadTask task);

  factory UploadController(
    StreamController<UploadProgress> progressStream,
    StreamedUpload streamedUpload,
    DataBundler dataBundler, {
    int numOfWorkers = 5,
    int maxTasksPerWorker = 5,
  }) {
    return _UploadController(
      progressStream: progressStream,
      streamedUpload: streamedUpload,
      dataBundler: dataBundler,
      numOfWorkers: numOfWorkers,
      maxTasksPerWorker: maxTasksPerWorker,
    );
  }
}

class _UploadController implements UploadController {
  final StreamController<UploadProgress> _progressStream;
  final StreamedUpload _streamedUpload;
  final DataBundler _dataBundler;
  final int _numOfWorkers;
  final int _maxTasksPerWorker;

  _UploadController({
    required StreamController<UploadProgress> progressStream,
    required StreamedUpload streamedUpload,
    required DataBundler dataBundler,
    int numOfWorkers = 5,
    int maxTasksPerWorker = 5,
  })  : _dataBundler = dataBundler,
        _numOfWorkers = numOfWorkers,
        _maxTasksPerWorker = maxTasksPerWorker,
        _progressStream = progressStream,
        _streamedUpload = streamedUpload {
    init();
  }

  bool _isCanceled = false;
  bool get isCanceled => _isCanceled;
  DateTime? _start;

  WorkerPool? workerPool;

  void init() {
    _isCanceled = false;
    late StreamSubscription subscription;

    subscription =
        _progressStream.stream.debounceTime(Duration(milliseconds: 100)).listen(
      (event) async {
        if (_isCanceled) {
          return;
        }

        _start ??= DateTime.now();

        _onProgressChange!(event);

        final finishedTasksLength =
            _failedTasks.length + _completedTasks.length;

        if (finishedTasksLength == tasks.length) {
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
  Future<void> cancel() async {
    workerPool?.cancel();
    _isCanceled = true;

    final cancelableTask = tasks.values
        .where((e) =>
            e.status != UploadStatus.complete &&
            e.status != UploadStatus.failed)
        .toList();

    final cancelTasksFuture = cancelableTask.map((task) async {
      await task.streamedUpload.cancel(task, this);

      task = task.copyWith(status: UploadStatus.canceled);

      _canceledTasks.putIfAbsent(task.id, () => task);

      updateProgress(task: task);
    });

    await Future.wait(cancelTasksFuture);

    _onCancel(_canceledTasks.values.toList());

    _progressStream.close();
  }

  @override
  void onCancel(Function(List<UploadTask> tasks) callback) {
    _onCancel = callback;
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
      if (task.status == UploadStatus.complete) {
        _completedTasks[task.id] = task;
      } else if (task.status == UploadStatus.failed) {
        _failedTasks[task.id] = task;
      }

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
    }

    _progressStream.add(_uploadProgress);

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

  void Function(List<UploadTask> tasks) _onCancel = (List<UploadTask> tasks) {
    print('Upload Canceled');
  };

  @override
  final Map<String, UploadTask> tasks = {};
  final Map<String, UploadTask> _completedTasks = {};
  final Map<String, UploadTask> _failedTasks = {};
  final Map<String, UploadTask> _canceledTasks = {};

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
      } else {
        if (task is FileUploadTask) {
          totalSize += task.metadata.size;
        }
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

  @override
  void sendTasks(Wallet wallet) {
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
      wallet: wallet,
      dataBundler: _dataBundler,
      uploadController: this,
      onTaskCompleted: (task) {
        updateProgress(task: task);
      },
    );
  }

  @override
  void addTask(UploadTask task) {
    tasks[task.id] = task;
  }

  @override
  void sendTask(UploadTask task, Wallet wallet, {Function()? onTaskCompleted}) {
    Worker(
      wallet: wallet,
      dataBundler: _dataBundler,
      uploadController: this,
      onTaskCompleted: () {
        onTaskCompleted?.call();
      },
    ).addTask(task);
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

class Worker {
  final Function() onTaskCompleted;
  final int maxTasks;
  final DataBundler dataBundler;
  final Wallet wallet;
  final UploadController uploadController;

  List<Future<void>> taskFutures = [];

  Worker({
    required this.onTaskCompleted,
    this.maxTasks = 5,
    required this.dataBundler,
    required this.wallet,
    required this.uploadController,
  });

  void addTask(UploadTask task) {
    if (taskFutures.length < maxTasks) {
      final future = _performUpload(task);
      taskFutures.add(future);

      future.then((_) {
        taskFutures.remove(future);
        onTaskCompleted();
      });
    }
  }

  Future<void> _performUpload(UploadTask task) async {
    // Your upload logic here
    /// Can be either a DataItemResult or a TransactionResult
    dynamic bundle;

    try {
      if (task is FileUploadTask) {
        task = task.copyWith(content: [task.metadata]);

        bundle = await dataBundler.createDataBundle(
          file: task.file,
          metadata: task.metadata,
          wallet: wallet,
          driveKey: task.encryptionKey,
          onStartBundleCreation: () {
            print('Creating bundle');
            task = task.copyWith(
              status: UploadStatus.creatingBundle,
            );

            uploadController.updateProgress(
              task: task,
            );
          },
          onStartMetadataCreation: () {
            print('Creating metadata');
            task = task.copyWith(
              status: UploadStatus.creatingMetadata,
            );

            uploadController.updateProgress(
              task: task,
            );
          },
        );
      } else if (task is FolderUploadTask) {
        // creates the bundle for folders
        bundle = await dataBundler.createDataBundleForEntities(
          entities: task.folders,
          wallet: wallet,
          driveKey: task.encryptionKey,
        );

        final folderBundle = (bundle as List<DataResultWithContents>).first;

        bundle = folderBundle.dataItemResult;
      }

      /// The upload can be canceled while the bundle is being created
      if (task.status == UploadStatus.canceled) {
        print('Upload canceled while bundle was being created');
        return;
      }

      if (bundle is TransactionResult) {
        task = task.copyWith(
          uploadItem: BundleTransactionUploadItem(
            size: bundle.dataSize,
            data: bundle,
          ),
        );
      } else if (bundle is DataItemResult) {
        task = task.copyWith(
          uploadItem: BundleDataItemUploadItem(
            size: bundle.dataItemSize,
            data: bundle,
          ),
        );
      } else {
        throw Exception('Unknown bundle type');
      }

      uploadController.updateProgress(
        task: task,
      );

      if (_isCanceled) {
        print('Upload canceled after bundle creation and before upload');
        return;
      }

      final value =
          await task.streamedUpload.send(task, wallet, uploadController);

      return value;
    } catch (e) {
      /// Adds the status failed to the upload task and stops the upload.
      task = task.copyWith(
        status: UploadStatus.failed,
      );
      uploadController.updateProgress(
        task: task,
      );
      print('Error: $e');
    }
  }

  void cancel() {
    _isCanceled = true;
  }

  bool _isCanceled = false;
}

class WorkerPool {
  final int numWorkers;
  final int maxTasksPerWorker;
  final List<UploadTask> taskQueue;
  final List<Worker> workers;
  final Wallet wallet;
  final DataBundler dataBundler;
  final UploadController uploadController;

  WorkerPool({
    required this.numWorkers,
    required this.maxTasksPerWorker,
    required this.taskQueue,
    required this.wallet,
    required Function(UploadTask task) onTaskCompleted,
    required this.dataBundler,
    required this.uploadController,
  }) : workers = List.generate(
          numWorkers,
          (index) => Worker(
            wallet: wallet,
            dataBundler: dataBundler,
            uploadController: uploadController,
            onTaskCompleted: () {},
          ),
        ) {
    _setWorkerCallbacks();
    _initializeWorkers();
  }

  void _setWorkerCallbacks() {
    for (var i = 0; i < numWorkers; i++) {
      workers[i] = Worker(
        wallet: wallet,
        dataBundler: dataBundler,
        uploadController: uploadController,
        onTaskCompleted: () {
          if (_isCanceled) {
            return;
          }

          _assignNextTask(i);
        },
      );
    }
  }

  void _initializeWorkers() {
    for (var i = 0; i < numWorkers; i++) {
      for (var j = 0; j < maxTasksPerWorker; j++) {
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
    for (var element in workers) {
      element.cancel();
    }
  }

  bool get isCanceled => _isCanceled;

  bool _isCanceled = false;
}

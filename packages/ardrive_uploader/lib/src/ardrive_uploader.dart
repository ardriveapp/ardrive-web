import 'dart:async';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/data_bundler.dart';
import 'package:ardrive_uploader/src/streamed_upload.dart';
import 'package:ardrive_uploader/src/turbo_upload_service_base.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart' hide Cipher;

enum UploadStatus {
  /// The upload is not started yet
  notStarted,

  /// The upload is in progress
  inProgress,

  /// The upload is paused
  paused,

  bundling,

  preparationDone,

  encryting,

  /// The upload is complete
  complete,

  /// The upload has failed
  failed,
}

class UploadProgress {
  final double progress;
  final int totalSize;
  final int totalUploaded;
  final List<UploadTask> task;

  DateTime? startTime;

  UploadProgress({
    required this.progress,
    required this.totalSize,
    required this.task,
    required this.totalUploaded,
    this.startTime,
  });

  UploadProgress copyWith({
    double? progress,
    int? totalSize,
    List<UploadTask>? task,
    int? totalUploaded,
    DateTime? startTime,
  }) {
    return UploadProgress(
      startTime: startTime ?? this.startTime,
      progress: progress ?? this.progress,
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

// tools
abstract class ArDriveUploader {
  Future<UploadController> upload({
    required IOFile file,
    required ARFSUploadMetadataArgs args,
    required Wallet wallet,
    SecretKey? driveKey,
  }) {
    throw UnimplementedError();
  }

  Future<UploadController> uploadFiles({
    required List<(ARFSUploadMetadataArgs, IOFile)> files,
    required Wallet wallet,
    SecretKey? driveKey,
  }) {
    throw UnimplementedError();
  }

  Future<UploadController> uploadEntity({
    required IOEntity entity,
    required ARFSUploadMetadataArgs args,
    required Wallet wallet,
    SecretKey? driveKey,
  }) {
    throw UnimplementedError();
  }

  factory ArDriveUploader({
    ARFSUploadMetadataGenerator? metadataGenerator,
    required Uri turboUploadUri,
  }) {
    metadataGenerator ??= ARFSUploadMetadataGenerator(
      tagsGenerator: ARFSTagsGenetator(
        appInfoServices: AppInfoServices(),
      ),
    );
    return _ArDriveUploader(
      turboUploadUri: turboUploadUri,
      dataBundler: ARFSDataBundlerStable(
        metadataGenerator,
      ),
      metadataGenerator: metadataGenerator,
    );
  }
}

class _ArDriveUploader implements ArDriveUploader {
  _ArDriveUploader({
    required DataBundler dataBundler,
    required ARFSUploadMetadataGenerator metadataGenerator,
    required Uri turboUploadUri,
    // TODO: pass the turboUploadUri as a parameter
  })  : _dataBundler = dataBundler,
        _metadataGenerator = metadataGenerator,
        _streamedUpload = TurboStreamedUpload(
          TurboUploadServiceImpl(
            turboUploadUri: turboUploadUri,
          ),
        );

  final StreamedUpload _streamedUpload;
  final DataBundler _dataBundler;
  final ARFSUploadMetadataGenerator _metadataGenerator;

  /// STABLE.
  @override
  Future<UploadController> upload({
    required IOFile file,
    required ARFSUploadMetadataArgs args,
    required Wallet wallet,
    SecretKey? driveKey,
  }) async {
    final metadata = await _metadataGenerator.generateMetadata(
      file,
      args,
    );

    final uploadController = UploadController(
      StreamController<UploadProgress>(),
    );

    var uploadTask =
        UploadTask(status: UploadStatus.notStarted, content: [metadata]);

    uploadController.updateProgress(task: uploadTask);

    /// Creation of the data bundle
    final createDataBundle = _dataBundler.createDataBundle(
      file: file,
      metadata: metadata,
      wallet: wallet,
      driveKey: driveKey,
      onStartBundling: () {
        uploadTask = uploadTask.copyWith(
          status: UploadStatus.bundling,
        );
        uploadController.updateProgress(
          task: uploadTask,
        );
      },
      onStartEncryption: () {
        uploadTask = uploadTask.copyWith(
          status: UploadStatus.encryting,
        );
        uploadController.updateProgress(
          task: uploadTask,
        );
      },
    );

    createDataBundle.then((bdi) {
      uploadTask = uploadTask.copyWith(
        dataItem: bdi,
        status: UploadStatus.preparationDone,
      );

      // print('BDI id: ${bdi.id}');

      uploadController.updateProgress(
        task: uploadTask,
      );

      // print('Starting to send data bundle to network');

      _streamedUpload.send(uploadTask, wallet, uploadController).then((value) {
        // print('Upload complete');
      }).catchError((err) {
        uploadController.onError(() => print('Error: $err'));
      });
    });

    // print('Upload started');

    return uploadController;
  }

  @override
  Future<UploadController> uploadEntity({
    required IOEntity entity,
    required ARFSUploadMetadataArgs args,
    required Wallet wallet,
    SecretKey? driveKey,
  }) async {
    // TODO: Start the implementation only for folders by now.
    // FIXME: only works for folders
    final metadata = await _metadataGenerator.generateMetadata(
      entity,
      args,
    );

    // print('Creating a new upload controller');

    final uploadController = UploadController(
      StreamController<UploadProgress>(),
    );

    /// Creation of the data bundle
    _dataBundler
        .createDataBundleForEntity(
      entity: entity,
      metadata: metadata,
      wallet: wallet,
      driveKey: driveKey,
      driveId: args.driveId!,
    )
        .then((dataItems) {
      // print('BDIs created');

      for (var dataItem in dataItems) {
        final uploadTask = UploadTask(
          dataItem: dataItem.dataItemResult,
          content: dataItem.contents,
        );

        // print('BDI id: ${dataItem.dataItemResult.id}');

        uploadTask.status = UploadStatus.preparationDone;
        // TODO: the upload controller should emit the send sending the tasks
        uploadController.updateProgress(
          task: uploadTask,
        );

        _streamedUpload
            .send(uploadTask, wallet, uploadController)
            .then((value) {
          // print('Upload complete');
        }).catchError((err) {
          uploadController.onError(() => print('Error: $err'));
        });
      }
    });

    return uploadController;
  }

  @override
  Future<UploadController> uploadFiles({
    required List<(ARFSUploadMetadataArgs, IOFile)> files,
    required Wallet wallet,
    SecretKey? driveKey,
  }) async {
    // print('Creating a new upload controller');

    final uploadController = UploadController(
      StreamController<UploadProgress>(),
    );

    /// Attaches the upload controller to the upload service
    _uploadFiles(
      files: files,
      wallet: wallet,
      controller: uploadController,
      driveKey: driveKey,
    );

    return uploadController;
  }

  Future _uploadFiles({
    required List<(ARFSUploadMetadataArgs, IOFile)> files,
    required Wallet wallet,
    SecretKey? driveKey,
    required UploadController controller,
  }) async {
    List<Future<void>> activeUploads = [];
    List<ARFSUploadMetadata> contents = [];
    List<UploadTask> tasks = [];
    int totalSize = 0;

    for (var f in files) {
      final metadata = await _metadataGenerator.generateMetadata(
        f.$2,
        f.$1,
      );

      final uploadTask = UploadTask(
        status: UploadStatus.notStarted,
        content: [metadata],
      );

      tasks.add(uploadTask);

      controller.updateProgress(task: uploadTask);

      contents.add(metadata);
    }

    for (int i = 0; i < files.length; i++) {
      int fileSize = await files[i].$2.length;

      while (activeUploads.length >= 50 ||
          totalSize + fileSize >= 500 * 1024 * 1024) {
        await Future.any(activeUploads);

        // Remove completed uploads and update totalSize
        int recalculatedSize = 0;
        List<Future<void>> ongoingUploads = [];

        for (var f in activeUploads) {
          // You need to figure out how to get the file size for the ongoing upload here
          // Add its size to recalculatedSize
          int ongoingFileSize = await files[i].$2.length;
          recalculatedSize += ongoingFileSize;

          ongoingUploads.add(f);
        }

        activeUploads = ongoingUploads;
        totalSize = recalculatedSize;
      }

      totalSize += fileSize;

      Future<void> uploadFuture = _uploadSingleFile(
        file: files[i].$2,
        uploadController: controller,
        wallet: wallet,
        driveKey: driveKey,
        metadata: contents[i],
        uploadTask: tasks[i],
      );

      uploadFuture.then((_) {
        activeUploads.remove(uploadFuture);
        totalSize -= fileSize;
      }).catchError((error) {
        activeUploads.remove(uploadFuture);
        totalSize -= fileSize;
        // TODO: Handle error
      });

      activeUploads.add(uploadFuture);
    }

    await Future.wait(activeUploads);
  }

  Future _uploadSingleFile({
    required IOFile file,
    required UploadController uploadController,
    required Wallet wallet,
    SecretKey? driveKey,
    required UploadTask uploadTask,
    required ARFSUploadMetadata metadata,
  }) async {
    final createDataBundle = _dataBundler.createDataBundle(
      file: file,
      metadata: metadata,
      wallet: wallet,
      driveKey: driveKey,
      onStartBundling: () {
        uploadTask = uploadTask.copyWith(
          status: UploadStatus.bundling,
        );
        uploadController.updateProgress(
          task: uploadTask,
        );
      },
      onStartEncryption: () {
        uploadTask = uploadTask.copyWith(
          status: UploadStatus.encryting,
        );
        uploadController.updateProgress(
          task: uploadTask,
        );
      },
    );

    final bdi = await createDataBundle;

    uploadTask = uploadTask.copyWith(
      dataItem: bdi,
      status: UploadStatus.preparationDone,
    );

    print('BDI id: ${bdi.id}');

    uploadController.updateProgress(
      task: uploadTask,
    );

    print('Starting to send data bundle to network');

    final value = await _streamedUpload
        .send(uploadTask, wallet, uploadController)
        .then((value) {})
        .catchError((err) {
      uploadController.onError(() => print('Error: $err'));
    });

    return value;
  }
}

class DataItemResultWithContents {
  final DataItemResult dataItemResult;
  final List<ARFSUploadMetadata> contents;

  DataItemResultWithContents({
    required this.dataItemResult,
    required this.contents,
  });
}

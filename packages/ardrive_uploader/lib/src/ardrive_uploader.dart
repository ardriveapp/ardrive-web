import 'dart:async';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/data_bundler.dart';
import 'package:ardrive_uploader/src/streamed_upload.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart' hide Cipher;

enum UploadType { turbo, d2n }

abstract class ArDriveUploader {
  Future<UploadController> upload({
    required IOFile file,
    required ARFSUploadMetadataArgs args,
    required Wallet wallet,
    SecretKey? driveKey,
    required UploadType type,
  }) {
    throw UnimplementedError();
  }

  Future<UploadController> uploadFiles({
    required List<(ARFSUploadMetadataArgs, IOFile)> files,
    required Wallet wallet,
    SecretKey? driveKey,
    required UploadType type,
  }) {
    throw UnimplementedError();
  }

  Future<UploadController> uploadEntities({
    required List<(ARFSUploadMetadataArgs, IOEntity)> entities,
    required Wallet wallet,
    SecretKey? driveKey,
    Function(ARFSUploadMetadata)? skipMetadataUpload,
    Function(ARFSUploadMetadata)? onCreateMetadata,
    required UploadType type,
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
      dataBundlerFactory: DataBundlerFactory(),
      metadataGenerator: metadataGenerator,
    );
  }
}

class _ArDriveUploader implements ArDriveUploader {
  _ArDriveUploader({
    required DataBundlerFactory dataBundlerFactory,
    required ARFSUploadMetadataGenerator metadataGenerator,
    required Uri turboUploadUri,
  })  : _dataBundlerFactory = dataBundlerFactory,
        _turboUploadUri = turboUploadUri,
        _metadataGenerator = metadataGenerator,
        _streamedUploadFactory = StreamedUploadFactory();

  final StreamedUploadFactory _streamedUploadFactory;
  final DataBundlerFactory _dataBundlerFactory;
  final ARFSUploadMetadataGenerator _metadataGenerator;
  final Uri _turboUploadUri;

  @override
  Future<UploadController> upload({
    required IOFile file,
    required ARFSUploadMetadataArgs args,
    required Wallet wallet,
    SecretKey? driveKey,
    required UploadType type,
  }) async {
    final uploadController = UploadController(
      StreamController<UploadProgress>(),
      _streamedUploadFactory.fromUploadType(type, _turboUploadUri),
      _dataBundlerFactory.createDataBundler(
        metadataGenerator: _metadataGenerator,
        type: type,
      ),
    );

    final metadata = await _metadataGenerator.generateMetadata(
      file,
      args,
    );

    final uploadTask = ARFSUploadTask(
      status: UploadStatus.notStarted,
      content: [metadata],
    );

    uploadController.addTask(uploadTask);

    uploadController.sendTasks(wallet);

    return uploadController;
  }

  @override
  Future<UploadController> uploadFiles({
    required List<(ARFSUploadMetadataArgs, IOFile)> files,
    required Wallet wallet,
    SecretKey? driveKey,
    required UploadType type,
  }) async {
    print('Creating a new upload controller using the upload type $type');

    final uploadController = UploadController(
      StreamController<UploadProgress>(),
      _streamedUploadFactory.fromUploadType(type, _turboUploadUri),
      _dataBundlerFactory.createDataBundler(
        metadataGenerator: _metadataGenerator,
        type: type,
      ),
    );

    for (var f in files) {
      final metadata = await _metadataGenerator.generateMetadata(
        f.$2,
        f.$1,
      );

      final fileTask = FileUploadTask(
        file: f.$2,
        metadata: metadata as ARFSFileUploadMetadata,
        encryptionKey: driveKey,
        streamedUpload: _streamedUploadFactory.fromUploadType(
          type,
          _turboUploadUri,
        ),
      );

      uploadController.addTask(fileTask);
    }

    uploadController.sendTasks(wallet);

    return uploadController;
  }

  Future _uploadFiles({
    required List<(ARFSUploadMetadataArgs, IOFile)> files,
    required Wallet wallet,
    SecretKey? driveKey,
    required UploadController controller,
    required UploadType type,
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

      final uploadTask = ARFSUploadTask(
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
        type: type,
      );

      uploadFuture.then((_) {
        activeUploads.remove(uploadFuture);
        totalSize -= fileSize;
      }).catchError((error) {
        activeUploads.remove(uploadFuture);
        totalSize -= fileSize;
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
    required UploadType type,
  }) async {
    final dataBundler = _dataBundlerFactory.createDataBundler(
      metadataGenerator: _metadataGenerator,
      type: type,
    );

    /// Can be either a DataItemResult or a TransactionResult
    late dynamic bundle;

    try {
      bundle = await dataBundler.createDataBundle(
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
    } catch (e) {
      /// Adds the status failed to the upload task and stops the upload.
      uploadTask = uploadTask.copyWith(
        status: UploadStatus.failed,
      );
      uploadController.updateProgress(
        task: uploadTask,
      );
      return;
    }

    switch (type) {
      case UploadType.d2n:
        uploadTask = uploadTask.copyWith(
          uploadItem: BundleTransactionUploadItem(
            data: bundle,
            size: bundle.dataSize,
          ),
        );
        break;
      case UploadType.turbo:
        uploadTask = uploadTask.copyWith(
          uploadItem: BundleDataItemUploadItem(
            data: bundle,
            size: bundle.dataItemSize,
          ),
          status: UploadStatus.preparationDone,
        );
        break;
    }

    uploadController.updateProgress(
      task: uploadTask,
    );

    final streamedUpload =
        _streamedUploadFactory.fromUploadType(type, _turboUploadUri);

    final value =
        await streamedUpload.send(uploadTask, wallet, uploadController);

    return value;
  }

  // TODO: Check it
  @override
  Future<UploadController> uploadEntities({
    required List<(ARFSUploadMetadataArgs, IOEntity)> entities,
    required Wallet wallet,
    SecretKey? driveKey,
    Function(ARFSUploadMetadata p1)? skipMetadataUpload,
    Function(ARFSUploadMetadata p1)? onCreateMetadata,
    UploadType type = UploadType.turbo,
  }) async {
    final dataBundler = _dataBundlerFactory.createDataBundler(
      metadataGenerator: _metadataGenerator,
      type: type,
    );

    final streamedUpload = _streamedUploadFactory.fromUploadType(
      type,
      _turboUploadUri,
    );

    final filesWitMetadatas = <(ARFSFileUploadMetadata, IOFile)>[];
    final folderMetadatas = <(ARFSFolderUploadMetatadata, IOEntity)>[];

    FolderUploadTask? folderUploadTask;

    for (var e in entities) {
      final metadata = await _metadataGenerator.generateMetadata(
        e.$2,
        e.$1,
      );

      if (metadata is ARFSFolderUploadMetatadata) {
        folderMetadatas.add((metadata, e.$2));
        continue;
      } else if (metadata is ARFSFileUploadMetadata) {
        filesWitMetadatas.add((metadata, e.$2 as IOFile));
      }
    }

    final uploadController = UploadController(
      StreamController<UploadProgress>(),
      streamedUpload,
      dataBundler,
    );

    if (folderMetadatas.isNotEmpty) {
      folderUploadTask = FolderUploadTask(
        folders: folderMetadatas,
        content: folderMetadatas.map((e) => e.$1).toList(),
        encryptionKey: driveKey,
        streamedUpload: _streamedUploadFactory.fromUploadType(
          type,
          _turboUploadUri,
        ),
      );

      uploadController.addTask(folderUploadTask);
    }

    for (var f in filesWitMetadatas) {
      final fileTask = FileUploadTask(
        file: f.$2,
        metadata: f.$1,
        encryptionKey: driveKey,
        streamedUpload: _streamedUploadFactory.fromUploadType(
          type,
          _turboUploadUri,
        ),
        content: [f.$1],
      );

      uploadController.addTask(fileTask);
    }

    if (folderUploadTask != null) {
      // first sends the upload task for the folder and then uploads the files
      uploadController.sendTask(folderUploadTask, wallet, onTaskCompleted: () {
        uploadController.sendTasks(wallet);
      });
    } else {
      uploadController.sendTasks(wallet);
    }

    return uploadController;
  }
}

class DataResultWithContents<T> {
  final T dataItemResult;
  final List<ARFSUploadMetadata> contents;

  DataResultWithContents({
    required this.dataItemResult,
    required this.contents,
  });
}

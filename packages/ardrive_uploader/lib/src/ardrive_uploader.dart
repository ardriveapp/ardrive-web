import 'dart:async';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/d2n_streamed_upload.dart';
import 'package:ardrive_uploader/src/data_bundler.dart';
import 'package:ardrive_uploader/src/turbo_streamed_upload.dart';
import 'package:ardrive_uploader/src/turbo_upload_service_base.dart';
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
    UploadType type = UploadType.turbo,
  }) {
    throw UnimplementedError();
  }

  Future<UploadController> uploadFiles({
    required List<(ARFSUploadMetadataArgs, IOFile)> files,
    required Wallet wallet,
    SecretKey? driveKey,
    UploadType type = UploadType.turbo,
  }) {
    throw UnimplementedError();
  }

  Future<UploadController> uploadEntities({
    required List<(ARFSUploadMetadataArgs, IOEntity)> entities,
    required Wallet wallet,
    SecretKey? driveKey,
    Function(ARFSUploadMetadata)? skipMetadataUpload,
    Function(ARFSUploadMetadata)? onCreateMetadata,
    UploadType type = UploadType.turbo,
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
    required DataBundler<ARFSUploadMetadata> dataBundler,
    required ARFSUploadMetadataGenerator metadataGenerator,
    required Uri turboUploadUri,
  })  : _dataBundler = dataBundler,
        _metadataGenerator = metadataGenerator,
        _turboStreamedUpload = TurboStreamedUpload(
          TurboUploadServiceImpl(
            turboUploadUri: turboUploadUri,
          ),
        ),
        _d2nStreamedUpload = D2NStreamedUpload();

  final TurboStreamedUpload _turboStreamedUpload;
  final D2NStreamedUpload _d2nStreamedUpload;
  final DataBundler<ARFSUploadMetadata> _dataBundler;
  final ARFSUploadMetadataGenerator _metadataGenerator;

  @override
  Future<UploadController> upload({
    required IOFile file,
    required ARFSUploadMetadataArgs args,
    required Wallet wallet,
    SecretKey? driveKey,
    UploadType type = UploadType.turbo,
  }) async {
    final metadata = await _metadataGenerator.generateMetadata(
      file,
      args,
    );

    await _dataBundler.createBundleDataTransaction(
        file: file, metadata: metadata, wallet: wallet);

    return UploadController(
      StreamController<UploadProgress>(),
      _turboStreamedUpload,
    );
  }

  @override
  Future<UploadController> uploadFiles({
    required List<(ARFSUploadMetadataArgs, IOFile)> files,
    required Wallet wallet,
    SecretKey? driveKey,
    UploadType type = UploadType.turbo,
  }) async {
    print('Creating a new upload controller using the upload type $type');

    final uploadController = UploadController(
      StreamController<UploadProgress>(),
      _turboStreamedUpload,
    );

    /// Attaches the upload controller to the upload service
    _uploadFiles(
      files: files,
      wallet: wallet,
      controller: uploadController,
      driveKey: driveKey,
      type: type,
    );

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

      print('Metadata: ${metadata.toJson().toString()}');

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
        type: type,
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
    required UploadType type,
  }) async {
    switch (type) {
      case UploadType.turbo:
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

        // TODO: verify if we are uploading for D2N or Turbo
        uploadTask = uploadTask.copyWith(
          dataItem: DataItemUploadTask(size: bdi.dataItemSize, data: bdi),
          status: UploadStatus.preparationDone,
        );

        print('BDI id: ${bdi.id}');
        print('BDI size: ${bdi.dataItemSize}');

        uploadController.updateProgress(
          task: uploadTask,
        );

        print('Starting to send data bundle to network');

        // uploads
        final value = await _turboStreamedUpload
            .send(uploadTask, wallet, uploadController)
            .then((value) {})
            .catchError((err) {
          uploadController.onError(() => print('Error: $err'));
        });

        return value;
      case UploadType.d2n:
        print('Creating a new upload controller using the upload type $type');
        final transactionResult =
            await _dataBundler.createBundleDataTransaction(
          file: file,
          metadata: metadata,
          wallet: wallet,
        );

        // adds the item for the upload
        uploadTask = uploadTask.copyWith(
          dataItem: TransactionUploadTask(
            data: transactionResult,
            size: transactionResult.dataSize,
          ),
        );

        // sends the upload
        _d2nStreamedUpload
            .send(uploadTask, wallet, uploadController)
            .then((value) {
          // print('Upload complete');
        }).catchError((err) {
          uploadController.onError(() => print('Error: $err'));
        });
        break;
    }
  }

  @override
  Future<UploadController> uploadEntities({
    required List<(ARFSUploadMetadataArgs, IOEntity)> entities,
    required Wallet wallet,
    SecretKey? driveKey,
    Function(ARFSUploadMetadata p1)? skipMetadataUpload,
    Function(ARFSUploadMetadata p1)? onCreateMetadata,
    UploadType type = UploadType.turbo,
  }) async {
    final entitiesWithMedata = <(ARFSUploadMetadata, IOEntity)>[];
    for (var e in entities) {
      final metadata = await _metadataGenerator.generateMetadata(
        e.$2,
        e.$1,
      );

      entitiesWithMedata.add((metadata, e.$2));
    }

    final folderMetadatas = entitiesWithMedata
        .where((element) => element.$2 is IOFolder)
        .map((e) => e.$1)
        .toList();

    final uploadController = UploadController(
      StreamController<UploadProgress>(),
      _turboStreamedUpload,
    );

    if (folderMetadatas.isNotEmpty) {
      switch (type) {
        case UploadType.turbo:
          final bundleForFolders =
              (await _dataBundler.createDataBundleForEntities(
            entities: entitiesWithMedata
                .where((element) => element.$2 is IOFolder)
                .toList(),
            wallet: wallet,
            driveKey: driveKey,
          ))
                  .first;

          // turbo:
          UploadTask folderBDITask = UploadTask(
            status: UploadStatus.notStarted,
            content: bundleForFolders.contents,
          );

          folderBDITask = folderBDITask.copyWith(
            dataItem: DataItemUploadTask(
              size: bundleForFolders.dataItemResult.dataItemSize,
              data: bundleForFolders.dataItemResult,
            ),
            status: UploadStatus.preparationDone,
          );

          uploadController.updateProgress(
            task: folderBDITask,
          );

          print('Starting to send data bundle to network');

          // TODO: uploads: for now, only works for turbo
          _turboStreamedUpload
              .send(folderBDITask, wallet, uploadController)
              .then((value) {})
              .catchError((err) {
            uploadController.onError(() => print('Error: $err'));
          });
        case UploadType.d2n:
          print('Creating a new upload controller using the upload type $type');
          final transactionResult =
              await _dataBundler.createBundleDataTransactionForEntities(
            entities: entitiesWithMedata
                .where((element) => element.$2 is IOFolder)
                .toList(),
            wallet: wallet,
            driveKey: driveKey,
          );

          UploadTask folderTransactionTask = UploadTask(
            status: UploadStatus.notStarted,
            content: transactionResult.first.contents,
          );

          // adds the item for the upload
          folderTransactionTask = folderTransactionTask.copyWith(
            dataItem: TransactionUploadTask(
              data: transactionResult.first.dataItemResult,
              size: transactionResult.first.dataItemResult.dataSize,
            ),
          );

          // sends the upload
          _d2nStreamedUpload
              .send(folderTransactionTask, wallet, uploadController)
              .then((value) {
            print('Upload complete');
          }).catchError((err) {
            uploadController.onError(() => print('Error: $err'));
          });
          break;
      }
    }

    _uploadFiles(
      files: entities.whereType<(ARFSUploadMetadataArgs, IOFile)>().toList(),
      wallet: wallet,
      driveKey: driveKey,
      controller: uploadController,
      type: type,
    );

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

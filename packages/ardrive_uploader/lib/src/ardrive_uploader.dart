import 'dart:async';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart' hide Cipher;
import 'package:flutter/foundation.dart';
import 'package:pst/pst.dart';

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
    Arweave? arweave,
    PstService? pstService,
  }) {
    metadataGenerator ??= ARFSUploadMetadataGenerator(
      tagsGenerator: ARFSTagsGenetator(
        appInfoServices: AppInfoServices(),
      ),
    );

    arweave ??= Arweave();
    pstService ??= PstService(
      communityOracle: CommunityOracle(
        ArDriveContractOracle([
          ContractOracle(WarpContractReader()),
        ]),
      ),
    );

    final dataBundlerFactory = DataBundlerFactory(
      arweaveService: arweave,
      pstService: pstService,
      metadataGenerator: metadataGenerator,
    );

    final streamedUploadFactory = StreamedUploadFactory(
      turboUploadUri: turboUploadUri,
    );

    return _ArDriveUploader(
      dataBundlerFactory: dataBundlerFactory,
      uploadFileStrategyFactory:
          UploadFileStrategyFactory(dataBundlerFactory, streamedUploadFactory),
      metadataGenerator: metadataGenerator,
      streamedUploadFactory: streamedUploadFactory,
    );
  }
}

class _ArDriveUploader implements ArDriveUploader {
  _ArDriveUploader({
    required DataBundlerFactory dataBundlerFactory,
    required ARFSUploadMetadataGenerator metadataGenerator,
    required UploadFileStrategyFactory uploadFileStrategyFactory,
    required StreamedUploadFactory streamedUploadFactory,
  })  : _dataBundlerFactory = dataBundlerFactory,
        _streamedUploadFactory = streamedUploadFactory,
        _metadataGenerator = metadataGenerator,
        _uploadFileStrategyFactory = uploadFileStrategyFactory;

  final DataBundlerFactory _dataBundlerFactory;
  final UploadFileStrategyFactory _uploadFileStrategyFactory;
  final ARFSUploadMetadataGenerator _metadataGenerator;
  final StreamedUploadFactory _streamedUploadFactory;

  @override
  Future<UploadController> upload({
    required IOFile file,
    required ARFSUploadMetadataArgs args,
    required Wallet wallet,
    SecretKey? driveKey,
    required UploadType type,
  }) async {
    final dataBundler = _dataBundlerFactory.createDataBundler(
      type,
    );

    final uploadFolderStrategy = UploadFolderStructureAsBundleStrategy(
      dataBundler: dataBundler,
      streamedUploadFactory: _streamedUploadFactory,
    );

    final uploadController = UploadController(
      StreamController<UploadProgress>(),
      UploadDispatcher(
        dataBundler: dataBundler,
        uploadStrategy: _uploadFileStrategyFactory.createUploadStrategy(
          type: type,
        ),
        uploadFolderStrategy: uploadFolderStrategy,
      ),
      numOfWorkers: 1,
      maxTasksPerWorker: 1,
    );

    final metadata = await _metadataGenerator.generateMetadata(
      file,
      arguments: args,
    );

    final uploadTask = FileUploadTask(
      file: file,
      metadata: metadata as ARFSFileUploadMetadata,
      content: [metadata],
      encryptionKey: driveKey,
      type: type,
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
    debugPrint('Creating a new upload controller using the upload type $type');

    final dataBundler = _dataBundlerFactory.createDataBundler(
      type,
    );

    final uploadFileStrategy = _uploadFileStrategyFactory.createUploadStrategy(
      type: type,
    );

    final uploadFolderStrategy = UploadFolderStructureAsBundleStrategy(
        dataBundler: dataBundler,
        streamedUploadFactory: _streamedUploadFactory);

    final uploadSender = UploadDispatcher(
      dataBundler: dataBundler,
      uploadStrategy: uploadFileStrategy,
      uploadFolderStrategy: uploadFolderStrategy,
    );

    final uploadController = UploadController(
      StreamController<UploadProgress>(),
      uploadSender,
      numOfWorkers: driveKey != null ? 3 : 5,
      maxTasksPerWorker: driveKey != null ? 1 : 3,
    );

    for (var f in files) {
      final ARFSUploadMetadataArgs metadataArgs = f.$1;
      final IOFile ioFile = f.$2;

      final metadata = await _metadataGenerator.generateMetadata(
        ioFile,
        arguments: metadataArgs,
      );

      final fileTask = FileUploadTask(
        file: ioFile,
        metadata: metadata as ARFSFileUploadMetadata,
        content: [metadata],
        encryptionKey: driveKey,
        type: type,
      );

      uploadController.addTask(fileTask);
    }

    uploadController.updateProgress();

    uploadController.sendTasks(wallet);

    return uploadController;
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
      type,
    );

    final uploadStrategy = _uploadFileStrategyFactory.createUploadStrategy(
      type: type,
    );

    final uploadFolderStrategy = UploadFolderStructureAsBundleStrategy(
        dataBundler: dataBundler,
        streamedUploadFactory: _streamedUploadFactory);

    final uploadSender = UploadDispatcher(
      dataBundler: dataBundler,
      uploadStrategy: uploadStrategy,
      uploadFolderStrategy: uploadFolderStrategy,
    );

    final filesWitMetadatas = <(ARFSFileUploadMetadata, IOFile)>[];
    final folderMetadatas = <(ARFSFolderUploadMetatadata, IOEntity)>[];

    FolderUploadTask? folderUploadTask;

    for (var e in entities) {
      final metadata = await _metadataGenerator.generateMetadata(
        e.$2,
        arguments: e.$1,
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
      uploadSender,
      numOfWorkers: driveKey != null ? 3 : 5,
      maxTasksPerWorker: driveKey != null ? 1 : 5,
    );

    if (folderMetadatas.isNotEmpty) {
      folderUploadTask = FolderUploadTask(
        folders: folderMetadatas,
        content: folderMetadatas.map((e) => e.$1).toList(),
        encryptionKey: driveKey,
        type: type,
      );

      uploadController.addTask(folderUploadTask);
    }

    for (var f in filesWitMetadatas) {
      final fileTask = FileUploadTask(
        file: f.$2,
        metadata: f.$1,
        encryptionKey: driveKey,
        content: [f.$1],
        type: type,
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

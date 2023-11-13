import 'dart:async';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/data_bundler.dart';
import 'package:ardrive_uploader/src/streamed_upload.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart' hide Cipher;
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
          ContractOracle(RedstoneContractReader()),
          ContractOracle(SmartweaveContractReader()),
        ]),
      ),
    );

    return _ArDriveUploader(
      turboUploadUri: turboUploadUri,
      dataBundlerFactory: DataBundlerFactory(),
      metadataGenerator: metadataGenerator,
      arweave: arweave,
      pstService: pstService,
    );
  }
}

class _ArDriveUploader implements ArDriveUploader {
  _ArDriveUploader({
    required DataBundlerFactory dataBundlerFactory,
    required ARFSUploadMetadataGenerator metadataGenerator,
    required Uri turboUploadUri,
    required Arweave arweave,
    required PstService pstService,
  })  : _dataBundlerFactory = dataBundlerFactory,
        _turboUploadUri = turboUploadUri,
        _metadataGenerator = metadataGenerator,
        _arweave = arweave,
        _pstService = pstService,
        _streamedUploadFactory = StreamedUploadFactory();

  final StreamedUploadFactory _streamedUploadFactory;
  final DataBundlerFactory _dataBundlerFactory;
  final Arweave _arweave;
  final PstService _pstService;
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
        arweaveService: _arweave,
        pstService: _pstService,
      ),
      numOfWorkers: 1,
      maxTasksPerWorker: 1,
    );

    final metadata = await _metadataGenerator.generateMetadata(
      file,
      args,
    );

    final uploadTask = FileUploadTask(
      file: file,
      metadata: metadata as ARFSFileUploadMetadata,
      content: [metadata],
      encryptionKey: driveKey,
      streamedUpload: _streamedUploadFactory.fromUploadType(
        type,
        _turboUploadUri,
      ),
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
        arweaveService: _arweave,
        pstService: _pstService,
      ),
      numOfWorkers: driveKey != null ? 3 : 5,
      maxTasksPerWorker: driveKey != null ? 1 : 5,
    );

    for (var f in files) {
      final ARFSUploadMetadataArgs metadataArgs = f.$1;
      final IOFile ioFile = f.$2;

      final metadata = await _metadataGenerator.generateMetadata(
        ioFile,
        metadataArgs,
      );

      final fileTask = FileUploadTask(
        file: ioFile,
        metadata: metadata as ARFSFileUploadMetadata,
        content: [metadata],
        encryptionKey: driveKey,
        streamedUpload: _streamedUploadFactory.fromUploadType(
          type,
          _turboUploadUri,
        ),
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
      metadataGenerator: _metadataGenerator,
      type: type,
      arweaveService: _arweave,
      pstService: _pstService,
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
      numOfWorkers: driveKey != null ? 3 : 5,
      maxTasksPerWorker: driveKey != null ? 1 : 5,
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

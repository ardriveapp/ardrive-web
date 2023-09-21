import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:arconnect/arconnect.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/turbo_upload_service.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart' hide Cipher;
import 'package:uuid/uuid.dart';

class ArDriveUploadProgress {
  final double progress;

  ArDriveUploadProgress(this.progress);
}

class UploadController {
  final StreamController<double> _controller =
      StreamController<double>.broadcast();

  bool _isCanceled = false;

  bool get isCanceled => _isCanceled;

  Stream<double> get progressStream => _controller.stream;

  void add(double progress) {
    if (_isCanceled) {
      print('Upload canceled');
      return;
    }

    _controller.add(progress);
  }

  void close() {
    _controller.close();
  }

  void cancel() {
    _isCanceled = true;
    _controller.close();
  }
}

// tools
abstract class ArDriveUploader {
  // TODO: implement the emition of these events
  // step of upload
  // creation of metadata
  // creation of the data item
  // encryption of data item
  // creation of bundle
  // upload of bundle
  //
  // progress

  Future<UploadController> upload({
    required IOFile file,
    required ARFSUploadMetadataArgs args,
    required Wallet wallet,
    SecretKey? driveKey,
  }) {
    throw UnimplementedError();
  }

  factory ArDriveUploader({
    ARFSUploadMetadataGenerator? metadataGenerator,
  }) {
    metadataGenerator ??= ARFSUploadMetadataGenerator(
      tagsGenerator: ARFSTagsGenetator(
        appInfoServices: AppInfoServices(),
      ),
    );
    return _ArDriveUploader(
      dataBundler: ARFSDataBundler(
        metadataGenerator: metadataGenerator,
      ),
    );
  }
}

class _ArDriveUploader implements ArDriveUploader {
  _ArDriveUploader({
    required ARFSDataBundler dataBundler,
    // TODO: pass the turboUploadUri as a parameter
  })  : _dataBundler = dataBundler,
        _uploadStreamer = TurboStreamedUpload(
          TurboUploadService(
            turboUploadUri: Uri.parse('https://upload.ardrive.dev'),
          ),
        );

  final StreamedUpload _uploadStreamer;
  final ARFSDataBundler _dataBundler;

  @override
  Future<UploadController> upload({
    required IOFile file,
    required ARFSUploadMetadataArgs args,
    required Wallet wallet,
    SecretKey? driveKey,
  }) async {
    /// Creation of the data bundle
    final bdi = await _dataBundler.createDataBundle(
      file: file,
      args: args,
      wallet: wallet,
      driveKey: driveKey,
    );

    print('Data bundle created');

    print('Starting to send data bundle to network');

    final networkRequestStream = await _uploadStreamer.send(bdi, wallet);

    return networkRequestStream;
  }
}

abstract class DataBundler<T> {
  Future<DataItemResult> createDataBundle({
    required IOFile file,
    required T args,
    required Wallet wallet,
    SecretKey? driveKey,
  });
}

class ARFSDataBundler implements DataBundler<ARFSUploadMetadataArgs> {
  final ARFSUploadMetadataGenerator _metadataGenerator;

  ARFSDataBundler({
    required ARFSUploadMetadataGenerator metadataGenerator,
  }) : _metadataGenerator = metadataGenerator;

  @override
  Future<DataItemResult> createDataBundle({
    required IOFile file,
    required ARFSUploadMetadataArgs args,
    required Wallet wallet,
    SecretKey? driveKey,
  }) async {
    final metadata = await _metadataGenerator.generateMetadata(
      file,
      args,
    );

    print('Metadata: ${metadata.toJson()}');

    print('Starting to generate data item');

    final dataGenerator = await _dataGenerator(
      dataStream: file.openReadStream,
      fileLength: await file.length,
      metadata: metadata,
      wallet: wallet,
      driveKey: driveKey,
    );

    print('Data item generated');

    print('Starting to generate metadata data item');

    final metadataDataItem = await _generateMetadataDataItem(
      metadata: metadata,
      dataStream: dataGenerator.$1,
      fileLength: await file.length,
      wallet: wallet,
      driveKey: driveKey,
    );

    print('Metadata data item generated');

    print('Starting to generate file data item');

    final fileDataItem = _generateFileDataItem(
      metadata: metadata,
      dataStream: dataGenerator.$1,
      fileLength: await file.length,
      cipherIv: dataGenerator.$2,
    );

    print('File data item generated');

    for (var tag in metadata.dataItemTags) {
      print('Data item tag: ${tag.name} - ${tag.value}');
    }

    for (var tag in metadata.entityMetadataTags) {
      print('Metadata tag: ${tag.name} - ${tag.value}');
    }

    final stopwatch = Stopwatch()..start();

    print('Starting to create bundled data item');

    final createBundledDataItem = createBundledDataItemTaskEither(
      dataItemFiles: [
        metadataDataItem,
        fileDataItem,
      ],
      wallet: wallet,
      tags: metadata.bundleTags.map((e) => createTag(e.name, e.value)).toList(),
    );

    final bundledDataItem = await createBundledDataItem.run();

    return bundledDataItem.match((l) {
      // TODO: handle error
      print('Error: $l');
      print(StackTrace.current);
      throw l;
    }, (bdi) async {
      print('Bundled data item created. ID: ${bdi.id}');
      print('Bundled data item size: ${bdi.dataItemSize} bytes');
      print(
          'The creation of the bundled data item took ${stopwatch.elapsedMilliseconds} ms');
      return bdi;
    });
  }

  Future<DataItemFile> _generateMetadataDataItem({
    required ARFSUploadMetadata metadata,
    required Stream<Uint8List> Function() dataStream,
    required int fileLength,
    required Wallet wallet,
    SecretKey? driveKey,
  }) async {
    final stopwatch = Stopwatch()..start(); // Start timer

    print('Initializing metadata data item generator...');

    Stream<Uint8List> Function() metadataGenerator;

    print('Creating DataItem...');
    final fileDataItemEither = createDataItemTaskEither(
        wallet: wallet,
        dataStream: dataStream,
        dataStreamSize: fileLength,
        tags: metadata.dataItemTags
            .map((e) => createTag(e.name, e.value))
            .toList());

    final fileDataItemResult = await fileDataItemEither.run();

    late String dataTxId;

    fileDataItemResult.match((l) {
      print('Error: $l');
      print(StackTrace.current);
    }, (fileDataItem) {
      dataTxId = fileDataItem.id;
      print('fileDataItemResult lenght: ${fileDataItem.dataSize} bytes');
      print('file length: $fileLength bytes');

      print('Data item created. ID: ${fileDataItem.id}');
    });

    final metadataJson = metadata.toJson()
      ..putIfAbsent('dataTxId', () => dataTxId);

    final metadataBytes = utf8
        .encode(jsonEncode(metadataJson))
        .map((e) => Uint8List.fromList([e]));

    if (driveKey != null) {
      print('DriveKey is not null. Starting metadata encryption...');

      final driveKeyData = Uint8List.fromList(await driveKey.extractBytes());

      final implMetadata = await cipherStreamEncryptImpl(Cipher.aes256ctr,
          keyData: driveKeyData);

      final encryptMetadataStreamResult =
          await implMetadata.encryptStreamGenerator(
        () => Stream.fromIterable(metadataBytes),
        metadataBytes.length,
      );

      print('Metadata encryption complete');

      final metadataCipherIv = encryptMetadataStreamResult.nonce;

      metadataGenerator = encryptMetadataStreamResult.streamGenerator;

      metadata.entityMetadataTags
          .add(Tag(EntityTag.cipherIv, encodeBytesToBase64(metadataCipherIv)));
    } else {
      print('DriveKey is null. Skipping metadata encryption.');
      metadataGenerator = () => Stream.fromIterable(metadataBytes);
    }

    print('Metadata size: ${metadataBytes.length} bytes');

    final metadataFile = DataItemFile(
      dataSize: metadataBytes.length,
      streamGenerator: metadataGenerator,
      tags: metadata.entityMetadataTags
          .map((e) => createTag(e.name, e.value))
          .toList(),
    );

    print(
        'Metadata data item generator complete. Elapsed time: ${stopwatch.elapsedMilliseconds} ms');

    return metadataFile;
  }

  DataItemFile _generateFileDataItem({
    required ARFSUploadMetadata metadata,
    required Stream<Uint8List> Function() dataStream,
    required int fileLength,
    Uint8List? cipherIv,
  }) {
    final tags =
        metadata.dataItemTags.map((e) => createTag(e.name, e.value)).toList();

    if (cipherIv != null) {
      tags.add(Tag(EntityTag.cipher, encodeBytesToBase64(cipherIv)));
    }

    final dataItemFile = DataItemFile(
      dataSize: fileLength,
      streamGenerator: dataStream,
      tags:
          metadata.dataItemTags.map((e) => createTag(e.name, e.value)).toList(),
    );

    return dataItemFile;
  }

  Future<(Stream<Uint8List> Function() generator, Uint8List? cipherIv)>
      _dataGenerator({
    required ARFSUploadMetadata metadata,
    required Stream<Uint8List> Function() dataStream,
    required int fileLength,
    required Wallet wallet,
    SecretKey? driveKey,
  }) async {
    final stopwatch = Stopwatch()..start(); // Start timer

    print('Initializing data generator...');

    Stream<Uint8List> Function() dataGenerator;
    Uint8List? cipherIv;

    if (driveKey != null) {
      print('DriveKey is not null. Starting encryption...');

      // Derive a file key from the user's drive key and the file id.
      // We don't salt here since the file id is already random enough but
      // we can salt in the future in cases where the user might want to revoke a file key they shared.
      final fileIdBytes = Uint8List.fromList(Uuid.parse(metadata.id));
      print('File ID bytes generated: ${fileIdBytes.length} bytes');

      final kdf = Hkdf(hmac: Hmac(Sha256()), outputLength: keyByteLength);
      print('KDF initialized');

      final fileKey = await kdf.deriveKey(
        secretKey: driveKey,
        info: fileIdBytes,
        nonce: Uint8List(1),
      );

      print('File key derived');

      final keyData = Uint8List.fromList(await fileKey.extractBytes());
      print('Key data extracted');

      final impl =
          await cipherStreamEncryptImpl(Cipher.aes256ctr, keyData: keyData);
      print('Cipher impl ready');

      final encryptStreamResult = await impl.encryptStreamGenerator(
        dataStream,
        fileLength,
      );

      print('Stream encryption complete');

      cipherIv = encryptStreamResult.nonce;
      dataGenerator = encryptStreamResult.streamGenerator;
    } else {
      print('DriveKey is null. Skipping encryption.');
      dataGenerator = dataStream;
    }

    print(
        'Data generator complete. Elapsed time: ${stopwatch.elapsedMilliseconds} ms');

    return (dataGenerator, cipherIv);
  }
}

abstract class StreamedUpload<T> {
  Future<UploadController> send(T handle, Wallet wallet);
}

class TurboStreamedUpload implements StreamedUpload<DataItemResult> {
  final TurboUploadService _turbo;
  final TabVisibilitySingleton _tabVisibility;

  TurboStreamedUpload(
    this._turbo, {
    TabVisibilitySingleton? tabVisibilitySingleton,
  }) : _tabVisibility = tabVisibilitySingleton ?? TabVisibilitySingleton();

  @override
  Future<UploadController> send(handle, Wallet wallet) async {
    final uploadController = UploadController();

    final nonce = const Uuid().v4();

    final publicKey = await safeArConnectAction<String>(
      _tabVisibility,
      (_) async {
        return wallet.getOwner();
      },
    );

    final signature = await safeArConnectAction<String>(
      _tabVisibility,
      (_) async {
        return signNonceAndData(
          nonce: nonce,
          wallet: wallet,
        );
      },
    );

    // gets the streamed request
    final streamedRequest = _turbo.postStream(
      wallet: wallet,
      headers: {
        'x-nonce': nonce,
        'x-address': publicKey,
        'x-signature': signature,
      },
      dataItem: handle,
      size: handle.dataItemSize,
      onSendProgress: (progress) {
        print('Progress: $progress');
        uploadController.add(progress);
      },
    );

    streamedRequest.then((response) {
      print('Response: ${response.statusCode}');
      uploadController.close();
    });

    return uploadController;
  }
}

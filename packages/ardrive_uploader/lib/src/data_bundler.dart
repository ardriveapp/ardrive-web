import 'dart:convert';

import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/constants.dart';
import 'package:ardrive_uploader/src/cost_calculator.dart';
import 'package:ardrive_uploader/src/utils/data_bundler_utils.dart';
import 'package:ardrive_uploader/src/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart' hide Cipher;
import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pst/pst.dart';
import 'package:uuid/uuid.dart';

abstract class DataBundler<T> {
  Future<List<DataItemFile>> createDataItemsForFile({
    required IOFile file,
    required ARFSFileUploadMetadata metadata,
    required Wallet wallet,
    SecretKey? driveKey,
    Function? onStartMetadataCreation,
    Function? onFinishMetadataCreation,
    Function? onStartBundleCreation,
    Function? onFinishBundleCreation,
  });

  Future<T> createDataBundle({
    required IOFile file,
    required ARFSFileUploadMetadata metadata,
    required Wallet wallet,
    List<Tag>? customBundleTags,
    SecretKey? driveKey,
    List<DataItemFile>? dataItemFiles,
    Function? onStartMetadataCreation,
    Function? onFinishMetadataCreation,
    Function? onStartBundleCreation,
    Function? onFinishBundleCreation,
  });

  Future<List<DataResultWithContents<T>>> createDataBundleForEntities({
    required List<(ARFSUploadMetadata, IOEntity)> entities,
    required Wallet wallet,
    List<Tag>? customBundleTags,
    SecretKey? driveKey,
  });
}

class DataTransactionBundler implements DataBundler<TransactionResult> {
  final ARFSUploadMetadataGenerator metadataGenerator;
  final UploadCostEstimateCalculatorForAR costCalculator;
  final PstService pstService;

  DataTransactionBundler(
    this.metadataGenerator,
    this.costCalculator,
    this.pstService,
  );

  @override
  Future<TransactionResult> createDataBundle({
    required IOFile file,
    required ARFSFileUploadMetadata metadata,
    required Wallet wallet,
    List<DataItemFile>? dataItemFiles,
    List<Tag>? customBundleTags,
    SecretKey? driveKey,
    Function? onStartEncryption,
    Function? onStartBundling,
    Function? onStartMetadataCreation,
    Function? onFinishMetadataCreation,
    Function? onStartBundleCreation,
    Function? onFinishBundleCreation,
  }) async {
    dataItemFiles ??= await createDataItemsForFile(
      file: file,
      metadata: metadata,
      wallet: wallet,
      driveKey: driveKey,
      onStartMetadataCreation: onStartMetadataCreation,
      onFinishMetadataCreation: onFinishMetadataCreation,
      onStartBundleCreation: onStartBundleCreation,
      onFinishBundleCreation: onFinishBundleCreation,
    );

    onStartBundleCreation?.call();

    final transactionResult = await createDataBundleTransaction(
      dataItemFiles: dataItemFiles,
      wallet: wallet,
      tags: getBundleTags(AppInfoServices(), customBundleTags)
          .map((e) => createTag(e.name, e.value))
          .toList(),
    );

    onFinishBundleCreation?.call();

    return transactionResult;
  }

  @override
  Future<List<DataResultWithContents<TransactionResult>>>
      createDataBundleForEntities({
    required List<(ARFSUploadMetadata, IOEntity)> entities,
    required Wallet wallet,
    List<Tag>? customBundleTags,
    SecretKey? driveKey,
  }) async {
    List<ARFSUploadMetadata> folderMetadatas = [];
    List<DataItemFile> folderDataItems = [];
    List<DataResultWithContents<TransactionResult>> transactionResults = [];

    if (entities.isEmpty) {
      throw Exception('The list of entities is empty');
    }

    for (var e in entities) {
      if (e.$2 is IOFile) {
        transactionResults.add(DataResultWithContents<TransactionResult>(
          dataItemResult: await createDataBundle(
            wallet: wallet,
            file: e.$2 as IOFile,
            metadata: e.$1 as ARFSFileUploadMetadata,
            driveKey: driveKey,
          ),
          contents: [e.$1],
        ));
      } else if (e.$2 is IOFolder) {
        final folderMetadata = e.$1;

        folderMetadatas.add(folderMetadata);

        final folderItem = await _generateMetadataDataItem(
          metadata: e.$1,
          wallet: wallet,
          driveKey: driveKey,
        );

        folderDataItems.add(folderItem);
      }
    }

    final bundleTags = getBundleTags(
      AppInfoServices(),
      customBundleTags,
    );

    final folderBundle = await createDataBundleTransaction(
      dataItemFiles: folderDataItems,
      wallet: wallet,
      tags: bundleTags.map((e) => createTag(e.name, e.value)).toList(),
    );

    /// All folders inside a single BDI, and the remaining files
    return [
      DataResultWithContents(
        dataItemResult: folderBundle,
        contents: folderMetadatas,
      ),
      ...transactionResults
    ];
  }

  Future<TransactionResult> createDataBundleTransaction({
    required final Wallet wallet,
    required final List<DataItemFile> dataItemFiles,
    required final List<Tag> tags,
  }) async {
    final dataItemList = await createDataItemResultFromDataItemFiles(
      dataItemFiles,
      wallet,
    );

    final dataBundleTaskEither =
        createDataBundleTaskEither(TaskEither.of(dataItemList));

    final bundledDataItemTags = [
      createTag('Bundle-Format', 'binary'),
      createTag('Bundle-Version', '2.0.0'),
      ...tags,
    ];

    final taskEither = await dataBundleTaskEither.run();
    final result = taskEither.match(
      (l) {
        throw l;
      },
      (r) async {
        int size = 0;

        await for (var chunk in r.stream()) {
          size += chunk.length;
        }

        print('Size of the bundled data item: $size bytes');

        final uploadCost = await costCalculator.calculateCost(
          totalSize: size,
        );

        final target = await pstService.getWeightedPstHolder();

        return createTransactionTaskEither(
          quantity: uploadCost.pstFee,
          wallet: wallet,
          dataStreamGenerator: r.stream,
          dataSize: size,
          tags: bundledDataItemTags,
          target: target.toString(),
        );
      },
    );

    return (await result).match(
      (l) {
        throw l;
      },
      (r) => r,
    ).run();
  }

  @override
  Future<List<DataItemFile>> createDataItemsForFile({
    required IOFile file,
    required ARFSFileUploadMetadata metadata,
    required Wallet wallet,
    SecretKey? driveKey,
    Function? onStartMetadataCreation,
    Function? onFinishMetadataCreation,
    Function? onStartBundleCreation,
    Function? onFinishBundleCreation,
  }) async {
    SecretKey? key;

    if (driveKey != null) {
      key = await deriveFileKey(
        driveKey,
        metadata.id,
        keyByteLength,
      );
      // onStartEncryption?.call();
    } else {
      // onStartBundling?.call();
    }

    // returns the encrypted or not file read stream and the cipherIv if it was encrypted
    final dataGenerator = await _dataGenerator(
      dataStream: file.openReadStream,
      fileLength: await file.length,
      metadata: metadata,
      wallet: wallet,
      encryptionKey: key,
    );

    onStartMetadataCreation?.call();

    final metadataDataItem = await _generateMetadataDataItemForFile(
      metadata: metadata,
      dataStream: dataGenerator,
      wallet: wallet,
      driveKey: driveKey,
    );

    final fileDataItem = _generateFileDataItem(
      metadata: metadata,
      dataStream: dataGenerator.$1,
      fileLength: dataGenerator.$4,
    );

    onFinishMetadataCreation?.call();

    return [metadataDataItem, fileDataItem];
  }
}

class BDIDataBundler implements DataBundler<DataItemResult> {
  final ARFSUploadMetadataGenerator metadataGenerator;

  BDIDataBundler(this.metadataGenerator);

  @override
  Future<DataItemResult> createDataBundle({
    required IOFile file,
    required ARFSFileUploadMetadata metadata,
    required Wallet wallet,
    List<Tag>? customBundleTags,
    SecretKey? driveKey,
    Function? onStartBundling,
    List<DataItemFile>? dataItemFiles,
    Function? onStartMetadataCreation,
    Function? onFinishMetadataCreation,
    Function? onStartBundleCreation,
    Function? onFinishBundleCreation,
  }) {
    return _createBundleStable(
      file: file,
      metadata: metadata,
      wallet: wallet,
      driveKey: driveKey,
      onStartBundling: onStartBundling,
      onFinishBundleCreation: onFinishBundleCreation,
      onStartBundleCreation: onStartBundleCreation,
      onStartMetadataCreation: onStartMetadataCreation,
      onFinishMetadataCreation: onFinishMetadataCreation,
    );
  }

  Future<DataItemResult> _createBundleStable({
    required IOFile file,
    required ARFSFileUploadMetadata metadata,
    required Wallet wallet,
    List<Tag>? customBundleTags,
    Function? onStartBundling,
    SecretKey? driveKey,
    Function? onStartMetadataCreation,
    Function? onFinishMetadataCreation,
    Function? onStartBundleCreation,
    Function? onFinishBundleCreation,
  }) async {
    final dataItemsFiles = await createDataItemsForFile(
      file: file,
      metadata: metadata,
      wallet: wallet,
      driveKey: driveKey,
      onStartMetadataCreation: onStartMetadataCreation,
      onFinishMetadataCreation: onFinishMetadataCreation,
      onStartBundleCreation: onStartBundleCreation,
      onFinishBundleCreation: onFinishBundleCreation,
    );

    onStartBundleCreation?.call();

    final bundleTags = getBundleTags(
      AppInfoServices(),
      customBundleTags,
    );

    final createBundledDataItem = createBundledDataItemTaskEither(
      dataItemFiles: dataItemsFiles,
      wallet: wallet,
      tags: bundleTags.map((e) => createTag(e.name, e.value)).toList(),
    );

    final bundledDataItem = await (await createBundledDataItem).run();

    onFinishBundleCreation?.call();

    return bundledDataItem.match((l) {
      print(StackTrace.current);
      throw l;
    }, (bdi) async {
      return bdi;
    });
  }

  @override
  Future<List<DataResultWithContents<DataItemResult>>>
      createDataBundleForEntities({
    required List<(ARFSUploadMetadata, IOEntity)> entities,
    required Wallet wallet,
    List<Tag>? customBundleTags,
    SecretKey? driveKey,
    Function(ARFSUploadMetadata metadata)? skipMetadata,
    Function(ARFSUploadMetadata metadata)? onMetadataCreated,
  }) async {
    List<ARFSUploadMetadata> folderMetadatas = [];
    List<DataItemFile> folderDataItems = [];
    List<DataResultWithContents<DataItemResult>> dataItemsResult = [];

    if (entities.isEmpty) {
      throw Exception('The list of entities is empty');
    }

    for (var e in entities) {
      if (e.$2 is IOFile) {
        final fileMetadata = e.$1;

        final dataItemResult = await _createBundleStable(
          file: e.$2 as IOFile,
          metadata: e.$1 as ARFSFileUploadMetadata,
          wallet: wallet,
        );

        dataItemsResult.add(DataResultWithContents(
            dataItemResult: dataItemResult, contents: [fileMetadata]));
      } else if (e.$2 is IOFolder) {
        final folderMetadata = e.$1;

        folderMetadatas.add(folderMetadata);

        final folderItem = await _generateMetadataDataItem(
          metadata: e.$1,
          wallet: wallet,
          driveKey: driveKey,
        );

        folderDataItems.add(folderItem);
      }
    }

    final bundleTags = getBundleTags(
      AppInfoServices(),
      customBundleTags,
    );

    final folderBDITask = await (await createBundledDataItemTaskEither(
      dataItemFiles: folderDataItems,
      wallet: wallet,
      tags: bundleTags.map((e) => createTag(e.name, e.value)).toList(),
    ))
        .run();

    // folder bdi
    final folderBDIResult = await folderBDITask.match((l) {
      throw l;
    }, (bdi) async {
      return bdi;
    });

    /// All folders inside a single BDI, and the remaining files
    return [
      DataResultWithContents(
        dataItemResult: folderBDIResult,
        contents: folderMetadatas,
      ),
      ...dataItemsResult
    ];
  }

  @override
  Future<List<DataItemFile>> createDataItemsForFile({
    required IOFile file,
    required ARFSFileUploadMetadata metadata,
    required Wallet wallet,
    SecretKey? driveKey,
    Function? onStartMetadataCreation,
    Function? onFinishMetadataCreation,
    Function? onStartBundleCreation,
    Function? onFinishBundleCreation,
  }) async {
    onStartMetadataCreation?.call();

    SecretKeyData? key;

    if (driveKey != null) {
      key = await deriveFileKey(
        driveKey,
        metadata.id,
        keyByteLength,
      );
    }

    // returns the encrypted or not file read stream and the cipherIv if it was encrypted
    final dataGenerator = await _dataGenerator(
      dataStream: file.openReadStream,
      fileLength: await file.length,
      metadata: metadata,
      wallet: wallet,
      encryptionKey: key,
    );

    final metadataDataItem = await _generateMetadataDataItemForFile(
      metadata: metadata,
      dataStream: dataGenerator,
      wallet: wallet,
      driveKey: driveKey,
    );

    onFinishMetadataCreation?.call();

    final fileDataItem = _generateFileDataItem(
      metadata: metadata,
      dataStream: dataGenerator.$1,
      fileLength: dataGenerator.$4,
    );

    logger.d('Metadata tags length: ${metadataDataItem.tags.length}');
    logger.d('DataItem tags length: ${fileDataItem.tags.length}');

    return [metadataDataItem, fileDataItem];
  }
}

DataItemFile _generateFileDataItem({
  required ARFSFileUploadMetadata metadata,
  required Stream<Uint8List> Function() dataStream,
  required int fileLength,
}) {
  final tags = metadata.getDataTags();

  final dataItemFile = DataItemFile(
    dataSize: fileLength,
    streamGenerator: dataStream,
    tags: tags.map((e) => createTag(e.name, e.value)).toList(),
  );

  return dataItemFile;
}

Future<DataItemFile> _generateMetadataDataItem({
  required ARFSUploadMetadata metadata,
  required Wallet wallet,
  SecretKey? driveKey,
}) async {
  Stream<Uint8List> Function() metadataStreamGenerator;

  final metadataJson = metadata.toJson();
  final metadataBytes =
      utf8.encode(jsonEncode(metadataJson)).map((e) => Uint8List.fromList([e]));
  int length;

  if (driveKey != null) {
    SecretKey key;
    if (metadata is ARFSFolderUploadMetatadata) {
      key = driveKey;
    } else {
      key = await deriveFileKey(
        driveKey,
        metadata.id,
        keyByteLength,
      );
    }

    final encryptedMetadata = await handleEncryption(
      key,
      () => Stream.fromIterable(metadataBytes),
      metadata.id,
      metadataBytes.length,
      keyByteLength,
    );

    metadataStreamGenerator = encryptedMetadata.$1;
    final metadataCipherIv = encryptedMetadata.$2;
    final cipher = encryptedMetadata.$3;

    metadata.setCipher(
        cipher: cipher, cipherIv: encodeBytesToBase64(metadataCipherIv!));

    length = encryptedMetadata.$4;
  } else {
    metadataStreamGenerator = () => Stream.fromIterable(metadataBytes);
    length = metadataBytes.length;
  }

  final metadataTask = createDataItemTaskEither(
    wallet: wallet,
    dataStream: metadataStreamGenerator,
    dataStreamSize: length,
    tags: metadata
        .getEntityMetadataTags()
        .map((e) => createTag(e.name, e.value))
        .toList(),
  ).flatMap((metadataDataItem) => TaskEither.of(metadataDataItem));

  final metadataTaskEither = await metadataTask.run();

  metadataTaskEither.match((l) {
    print(StackTrace.current);
    throw l;
  }, (metadataDataItem) {
    metadata.setMetadataTxId = metadataDataItem.id;
    return metadataDataItem;
  });

  return DataItemFile(
    dataSize: length,
    streamGenerator: metadataStreamGenerator,
    tags: metadata
        .getEntityMetadataTags()
        .map((e) => createTag(e.name, e.value))
        .toList(),
  );
}

Future<DataItemFile> _generateMetadataDataItemForFile({
  required ARFSFileUploadMetadata metadata,
  required (
    Stream<Uint8List> Function(),
    Uint8List? dataStream,
    String? cipher,
    int fileLength
  ) dataStream,
  required Wallet wallet,
  SecretKey? driveKey,
}) async {
  final dataItemTags = metadata.getDataTags();

  if (driveKey != null) {
    final cipher = dataStream.$3;
    final cipherIv = dataStream.$2;

    metadata.setDataCipher(
        cipher: cipher!, cipherIv: encodeBytesToBase64(cipherIv!));
  }

  final dataStreamGenerator = dataStream.$1;
  final dataStreamSize = dataStream.$4;

  final fileDataItemEither = createDataItemTaskEither(
    wallet: wallet,
    dataStream: dataStreamGenerator,
    dataStreamSize: dataStreamSize,
    tags: dataItemTags.map((e) => createTag(e.name, e.value)).toList(),
  );

  final fileDataItemResult = await fileDataItemEither.run();

  fileDataItemResult.match((l) {
    throw l;
  }, (fileDataItem) {
    metadata.setDataTxId = fileDataItem.id;
    if (metadata.licenseDefinitionTxId != null) {
      metadata.setLicenseTxId = fileDataItem.id;
    }
  });

  int metadataLength;

  final metadataBytes = utf8
      .encode(jsonEncode(metadata.toJson()))
      .map((e) => Uint8List.fromList([e]));

  Stream<Uint8List> Function() metadataGenerator;

  if (driveKey != null) {
    final fileKey = await deriveFileKey(
      driveKey,
      metadata.id,
      keyByteLength,
    );

    final result = await handleEncryption(
      fileKey,
      () => Stream.fromIterable(metadataBytes),
      metadata.id,
      metadataBytes.length,
      keyByteLength,
    );

    metadataGenerator = result.$1;
    metadataLength = result.$4;

    final metadataCipherIv = result.$2;
    final metadataCipher = result.$3;

    metadata.setCipher(
        cipher: metadataCipher,
        cipherIv: encodeBytesToBase64(metadataCipherIv!));
  } else {
    metadataGenerator = () => Stream.fromIterable(metadataBytes);
    metadataLength = metadataBytes.length;
  }

  final metadataTask = createDataItemTaskEither(
    wallet: wallet,
    dataStream: metadataGenerator,
    dataStreamSize: metadataLength,
    tags: metadata
        .getEntityMetadataTags()
        .map((e) => createTag(e.name, e.value))
        .toList(),
  ).flatMap((metadataDataItem) => TaskEither.of(metadataDataItem));

  final metadataTaskEither = await metadataTask.run();

  metadataTaskEither.match((l) {
    throw l;
  }, (metadataDataItem) {
    metadata.setMetadataTxId = metadataDataItem.id;
    return metadataDataItem;
  });

  return DataItemFile(
    dataSize: metadataLength,
    streamGenerator: metadataGenerator,
    tags: metadata
        .getEntityMetadataTags()
        .map((e) => createTag(e.name, e.value))
        .toList(),
  );
}

// ignore: constant_identifier_names
const AES256CTR = Cipher.aes256ctr;
// ignore: constant_identifier_names
const AES256GCM = Cipher.aes256gcm;
// ignore: non_constant_identifier_names
final UNIT_BYTE_LIST = Uint8List(1);

Future<SecretKeyData> deriveFileKey(
    SecretKey driveKey, String fileId, int keyByteLength) async {
  final fileIdBytes = Uint8List.fromList(Uuid.parse(fileId));
  final kdf = Hkdf(hmac: Hmac(Sha256()), outputLength: keyByteLength);
  return await kdf.deriveKey(
      secretKey: driveKey, info: fileIdBytes, nonce: UNIT_BYTE_LIST);
}

Future<
    (
      Stream<Uint8List> Function(),
      Uint8List? cipherIv,
      String cipher,
      int fileLength
    )> handleEncryption(
  SecretKey encryptionKey,
  Stream<Uint8List> Function() dataStream,
  String fileId,
  int fileLength,
  int keyByteLength,
) async {
  final keyData = Uint8List.fromList(await encryptionKey.extractBytes());
  Stream<Uint8List> Function() dataStreamGenerator;
  Uint8List nonce;
  String cipher;
  int length;

  if (fileLength < maxSizeSupportedByGCMEncryption) {
    // uses GCM
    final impl = cipherBufferImpl(AES256GCM);
    cipher = AES256GCM;
    final data = await concatenateUint8ListStream(dataStream());
    final encryptStreamResult =
        await impl.encrypt(data.toList(), secretKey: encryptionKey);
    final encryptedData = encryptStreamResult.concatenation(nonce: false);
    dataStreamGenerator = () => Stream.fromIterable([encryptedData]);
    nonce = Uint8List.fromList(encryptStreamResult.nonce);
    length = encryptedData.length;
  } else {
    final impl = await cipherStreamEncryptImpl(AES256CTR, keyData: keyData);
    final encryptStreamResult =
        await impl.encryptStreamGenerator(dataStream, fileLength);
    cipher = AES256CTR;
    dataStreamGenerator = encryptStreamResult.streamGenerator;
    nonce = encryptStreamResult.nonce;
    length = fileLength;
  }

  return (
    dataStreamGenerator,
    nonce,
    cipher,
    length,
  );
}

Future<
    (
      Stream<Uint8List> Function() generator,
      Uint8List? cipherIv,
      String? cipher,
      int fileSize
    )> _dataGenerator({
  required ARFSUploadMetadata metadata,
  required Stream<Uint8List> Function() dataStream,
  required int fileLength,
  required Wallet wallet,
  SecretKey? encryptionKey,
}) async {
  if (encryptionKey != null) {
    return await handleEncryption(
        encryptionKey, dataStream, metadata.id, fileLength, keyByteLength);
  } else {
    return (
      dataStream,
      null,
      null,
      fileLength,
    );
  }
}

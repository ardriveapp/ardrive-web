import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart' as arweave;
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart' hide Cipher;

abstract class ArDriveDownloader {
  Future<Stream<double>> downloadFile({
    required TransactionCommonMixin dataTx,
    required int fileSize,
    required String fileName,
    required DateTime lastModifiedDate,
    required String contentType,
    required bool isManifest,
    Completer<String>? cancelWithReason,
    SecretKey? fileKey,
    String? cipher,
    String? cipherIvString,
  });
  Future<Uint8List> downloadToMemory({
    required TransactionCommonMixin dataTx,
    required int fileSize,
    required String fileName,
    required DateTime lastModifiedDate,
    required String contentType,
    required bool isManifest,
    Completer<String>? cancelWithReason,
    SecretKey? fileKey,
    String? cipher,
    String? cipherIvString,
  });
  Future<void> abortDownload();

  factory ArDriveDownloader({
    required IOFileAdapter ioFileAdapter,
    required ArDriveIO ardriveIo,
    required ArweaveService arweave,
  }) {
    return _ArDriveDownloader(ioFileAdapter, ardriveIo, arweave);
  }
}

class _ArDriveDownloader implements ArDriveDownloader {
  final IOFileAdapter _ioFileAdapter;
  final ArDriveIO _ardriveIo;
  final ArweaveService _arweave;

  _ArDriveDownloader(this._ioFileAdapter, this._ardriveIo, this._arweave);

  final Completer<String> _cancelWithReason = Completer<String>();

  final StreamController<LinearProgress> downloadProgressController =
      StreamController<LinearProgress>.broadcast();

  Stream<LinearProgress> get downloadProgress =>
      downloadProgressController.stream;

  @override
  Future<Stream<double>> downloadFile({
    required TransactionCommonMixin dataTx,
    required int fileSize,
    required String fileName,
    required DateTime lastModifiedDate,
    required String contentType,
    required bool isManifest,
    Completer<String>? cancelWithReason,
    SecretKey? fileKey,
    String? cipher,
    String? cipherIvString,
  }) async {
    final saveStream = await _getDecryptedStream(
      dataTx: dataTx,
      fileSize: fileSize,
      fileName: fileName,
      lastModifiedDate: lastModifiedDate,
      contentType: contentType,
      isManifest: isManifest,
      fileKey: fileKey,
      cipher: cipher,
      cipherIvString: cipherIvString,
    );

    final file = await _ioFileAdapter.fromReadStreamGenerator(
      ([s, e]) => saveStream,
      fileSize,
      name: fileName,
      lastModifiedDate: lastModifiedDate,
    );

    final finalize = Completer<bool>();

    Future.any([
      _cancelWithReason.future.then((_) => false),
    ]).then((value) => finalize.complete(value)).catchError((e) {
      logger.d('Download aborted');
      finalize.complete(false);
    });

    bool? saveResult;
    var bytesSaved = 0;

    logger.i('Saving file...');

    final progressController = StreamController<double>();

    final subscription =
        _ardriveIo.saveFileStream(file, finalize).listen((saveStatus) {
      if (saveStatus.saveResult == null) {
        final progress = saveStatus.bytesSaved / saveStatus.totalBytes;
        bytesSaved += saveStatus.bytesSaved;

        logger.d('Saving file progress: ${progress * 100}%');

        progressController.sink.add(progress * 100);
      } else {
        saveResult = saveStatus.saveResult!;
      }
    });

    subscription.onDone(() async {
      if (_cancelWithReason.isCompleted) {
        progressController.addError(const DownloadCancelledException());
      }

      logger.d('File saved with success');

      progressController.close();
      subscription.cancel();
    });

    subscription.onError((e, s) {
      logger.e(
        'Failed to download of save the file. Closing progressController...',
        e,
        s,
      );
      if (saveResult != true) {
        // verify if the download was aborted before starting the save
        if (bytesSaved == 0) {
          progressController.addError(const DownloadCancelledException());
        }

        progressController.addError(Exception('Failed to save file'));
      }
      // TODO: we can show a different message for different errors e.g. when `e` is ActionCanceledException
      progressController.addError(e);
      progressController.close();
      return;
    });

    return progressController.stream;
  }

  @override
  Future<void> abortDownload() {
    _cancelWithReason.complete('Download aborted');
    logger.d('Download aborted');
    return Future.value();
  }

  Future<Stream<Uint8List>> _getManifestStream(String dataTxId) async {
    final urlString = '${_arweave.client.api.gatewayUrl.origin}/raw/$dataTxId';

    logger.i('The file is a manifest. Downloading it from $urlString');

    final dataRes = await ArDriveHTTP().getAsBytes(urlString);

    return Stream.fromIterable([dataRes.data]);
  }

  Future<Stream<Uint8List>> _getFileStream({
    required TransactionCommonMixin dataTx,
    required int fileSize,
    required String fileName,
    required DateTime lastModifiedDate,
    required String contentType,
    SecretKey? fileKey,
    String? cipher,
    String? cipherIvString,
  }) async {
    logger.d('The file is not a manifest. Downloading it from Arweave...');

    /// Disables the verification when the file was uploaded by the CLI
    final verifyDownload = dataTx.getTag(EntityTag.appName) == 'ArDrive-CLI';

    logger.d('verifying download: $verifyDownload');

    final streamDownloadResponse = await arweave.download(
      txId: dataTx.id,
      onProgress: (progress, speed) => logger.d(progress.toString()),
      verifyDownload: verifyDownload,
    );

    final streamDownload = streamDownloadResponse.$1;

    final isPrivateFile =
        fileKey != null && cipher != null && cipherIvString != null;

    if (isPrivateFile) {
      logger.d('Decrypting file...');

      final cipherIv = decodeBase64ToBytes(cipherIvString);

      final keyData = Uint8List.fromList(await fileKey.extractBytes());

      final isAValidCipher =
          cipher == Cipher.aes256ctr || cipher == Cipher.aes256gcm;

      if (isAValidCipher) {
        logger.d('Decrypting file with cipher: $cipher');

        return decryptTransactionDataStream(
          cipher,
          cipherIv,
          streamDownload.transform(listIntToUint8ListTransformer),
          keyData,
          fileSize,
        );
      } else {
        logger.e('Unknown cipher: $cipher. Throwing exception.');
        throw Exception('Unknown cipher: $cipher');
      }
    }

    logger.d('No cipher found. Saving file as is...');
    return streamDownload.transform(listIntToUint8ListTransformer);
  }

  Future<Stream<Uint8List>> _getDecryptedStream({
    required TransactionCommonMixin dataTx,
    required int fileSize,
    required String fileName,
    required DateTime lastModifiedDate,
    required String contentType,
    required bool isManifest,
    SecretKey? fileKey,
    String? cipher,
    String? cipherIvString,
  }) async {
    if (AppPlatform.isMobile) {
      final isPrivateFile =
          fileKey != null && cipher != null && cipherIvString != null;

      if (isPrivateFile && cipher == Cipher.aes256gcm) {
        final streamDownload = (await arweave.download(
          txId: dataTx.id,
          onProgress: (progress, speed) => logger.d(progress.toString()),
        ))
            .$1;

        final decryptedData = await decryptTransactionData(
          cipher,
          cipherIvString,
          await streamDownload.toList().then((chunks) =>
              Uint8List.fromList(chunks.expand((chunk) => chunk).toList())),
          fileKey,
        );

        return Stream.value(decryptedData);
      }
    }

    if (isManifest) {
      return _getManifestStream(dataTx.id);
    }

    return _getFileStream(
      dataTx: dataTx,
      fileSize: fileSize,
      fileName: fileName,
      lastModifiedDate: lastModifiedDate,
      contentType: contentType,
      fileKey: fileKey,
      cipher: cipher,
      cipherIvString: cipherIvString,
    );
  }

  @override
  Future<Uint8List> downloadToMemory({
    required TransactionCommonMixin dataTx,
    required int fileSize,
    required String fileName,
    required DateTime lastModifiedDate,
    required String contentType,
    required bool isManifest,
    Completer<String>? cancelWithReason,
    SecretKey? fileKey,
    String? cipher,
    String? cipherIvString,
  }) async {
    final stream = await _getDecryptedStream(
      dataTx: dataTx,
      fileSize: fileSize,
      fileName: fileName,
      lastModifiedDate: lastModifiedDate,
      contentType: contentType,
      isManifest: isManifest,
      fileKey: fileKey,
      cipher: cipher,
      cipherIvString: cipherIvString,
    );

    final data = await stream.toList();
    return Uint8List.fromList(data.expand((element) => element).toList());
  }
}

class DownloadCancelledException implements Exception {
  const DownloadCancelledException();

  @override
  String toString() {
    return 'Download cancelled';
  }
}

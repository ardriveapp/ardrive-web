import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/download/download_exceptions.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart' hide Cipher;

abstract class ArDriveDownloader {
  Future<Stream<double>> downloadFile({
    required String txId,
    required int fileSize,
    required String fileName,
    required DateTime lastModifiedDate,
    required String contentType,
    required bool isManifest,
    Completer<String>? cancelWithReason,
    SecretKey? fileKey,
    String? cipher,
    String? cipherIvString,
    bool verifyDownload,
  });
  Future<Uint8List> downloadToMemory({
    required String txId,
    required int fileSize,
    required String fileName,
    required DateTime lastModifiedDate,
    required String contentType,
    required bool isManifest,
    Completer<String>? cancelWithReason,
    SecretKey? fileKey,
    String? cipher,
    String? cipherIvString,
    bool verifyDownload,
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
    required String txId,
    required int fileSize,
    required String fileName,
    required DateTime lastModifiedDate,
    required String contentType,
    required bool isManifest,
    Completer<String>? cancelWithReason,
    SecretKey? fileKey,
    String? cipher,
    String? cipherIvString,
    bool verifyDownload = false,
  }) async {
    if (AppPlatform.isMobile) {
      final isPrivateFile =
          fileKey != null && cipher != null && cipherIvString != null;

      if (isPrivateFile && cipher == Cipher.aes256gcm) {
        return _getDartVMGCMDecryptStream(
          cipher,
          cipherIvString,
          (await _arweave.gatewayFallback.downloadWithFallback(
            txId: txId,
            primaryClient: _arweave.client,
            onProgress: (progress, speed) => logger.d(progress.toString()),
          ))
              .$1,
          fileSize,
          fileName,
          lastModifiedDate,
          contentType,
          fileKey,
        );
      }
    }

    Stream<Uint8List> saveStream;

    if (isManifest) {
      saveStream = await _getManifestStream(txId);
    } else {
      saveStream = await _getFileStream(
        txId: txId,
        fileSize: fileSize,
        fileName: fileName,
        lastModifiedDate: lastModifiedDate,
        contentType: contentType,
        fileKey: fileKey,
        cipher: cipher,
        cipherIvString: cipherIvString,
        verifyDownload: verifyDownload,
      );
    }

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
    logger.i('The file is a manifest. Downloading with gateway fallback...');

    final response = await _arweave.gatewayFallback
        .fetchManifestWithFallback(dataTxId, _arweave.client);

    return Stream.fromIterable(
        [Uint8List.fromList(response.bodyBytes)]);
  }

  Future<Stream<Uint8List>> _getFileStream({
    required String txId,
    required int fileSize,
    required String fileName,
    required DateTime lastModifiedDate,
    required String contentType,
    SecretKey? fileKey,
    String? cipher,
    String? cipherIvString,
    bool verifyDownload = false,
  }) async {
    logger.d('The file is not a manifest. Downloading it from Arweave...');

    logger.d('verifying download: $verifyDownload');

    final streamDownloadResponse =
        await _arweave.gatewayFallback.downloadWithFallback(
      txId: txId,
      primaryClient: _arweave.client,
      onProgress: (progress, speed) => logger.d(progress.toString()),
      verifyDownload: verifyDownload,
    );

    final rawStream = streamDownloadResponse.$1;

    // Wrap with stall detection — throw if no chunk arrives within 60s
    final streamDownload = _withStallDetection(rawStream, txId);

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

  static const _stallTimeout = Duration(seconds: 60);

  /// Wraps a download stream with stall detection. After the first chunk
  /// arrives, if no subsequent chunk arrives within [_stallTimeout], emits
  /// a [DownloadStalledException]. If the stream completes before any chunks
  /// (empty file), no stall error is raised.
  Stream<List<int>> _withStallDetection(
      Stream<List<int>> source, String txId) {
    final controller = StreamController<List<int>>();
    Timer? stallTimer;
    void resetTimer() {
      stallTimer?.cancel();
      stallTimer = Timer(_stallTimeout, () {
        controller.addError(DownloadStalledException(txId, _stallTimeout));
        controller.close();
      });
    }

    final subscription = source.listen(
      (chunk) {
        resetTimer();
        controller.add(chunk);
      },
      onError: (Object e, StackTrace s) {
        stallTimer?.cancel();
        controller.addError(e, s);
      },
      onDone: () {
        stallTimer?.cancel();
        controller.close();
      },
    );

    controller.onCancel = () {
      stallTimer?.cancel();
      subscription.cancel();
    };

    return controller.stream;
  }

  Stream<double> _getDartVMGCMDecryptStream(
    String cipher,
    String cipherIvString,
    Stream<List<int>> streamDownload,
    int fileSize,
    String fileName,
    DateTime lastModifiedDate,
    String contentType,
    SecretKey fileKey,
  ) async* {
    List<int> bytes = [];

    await for (var chunk in streamDownload) {
      bytes.addAll(chunk);
      yield bytes.length / fileSize * 100;
    }

    final encryptedData = await decryptTransactionData(
      cipher,
      cipherIvString,
      Uint8List.fromList(bytes),
      fileKey,
    );

    _ardriveIo.saveFile(
      await IOFile.fromData(encryptedData,
          name: fileName,
          lastModifiedDate: lastModifiedDate,
          contentType: contentType),
    );

    return;
  }

  @override
  Future<Uint8List> downloadToMemory({
    required String txId,
    required int fileSize,
    required String fileName,
    required DateTime lastModifiedDate,
    required String contentType,
    required bool isManifest,
    Completer<String>? cancelWithReason,
    SecretKey? fileKey,
    String? cipher,
    String? cipherIvString,
    bool verifyDownload = false,
  }) async {
    final stream = await _getFileStream(
      txId: txId,
      fileSize: fileSize,
      fileName: fileName,
      lastModifiedDate: lastModifiedDate,
      contentType: contentType,
      fileKey: fileKey,
      cipher: cipher,
      cipherIvString: cipherIvString,
      verifyDownload: verifyDownload,
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

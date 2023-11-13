import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:arweave/arweave.dart' as arweave;
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart' hide Cipher;

abstract class ArDriveDownloader {
  Future<Stream<double>> downloadFile({
    required String dataTx,
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
    required String dataTx,
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
    Stream<Uint8List> saveStream;

    if (isManifest) {
      final urlString = isManifest
          ? '${_arweave.client.api.gatewayUrl.origin}/raw/$dataTx'
          : '${_arweave.client.api.gatewayUrl.origin}/$dataTx';

      logger.i('Downloading manifest...');

      final dataRes = await ArDriveHTTP().getAsBytes(urlString);

      saveStream = Stream.fromIterable([dataRes.data]);
    } else {
      logger.d('Downloading file...');

      final streamDownloadResponse = await arweave.download(
        txId: dataTx,
        onProgress: (progress, speed) => logger.d(progress.toString()),
      );

      final streamDownload = streamDownloadResponse.$1;

      if (fileKey != null && cipher != null && cipherIvString != null) {
        logger.d('Decrypting file...');

        final cipherIv = decodeBase64ToBytes(cipherIvString);

        final keyData = Uint8List.fromList(await fileKey.extractBytes());

        if (cipher == Cipher.aes256ctr || cipher == Cipher.aes256gcm) {
          logger.d('Decrypting file with cipher: $cipher');

          saveStream = await decryptTransactionDataStream(
            cipher,
            cipherIv,
            streamDownload.transform(transformer),
            keyData,
            fileSize,
          );
        } else {
          logger.e('Unknown cipher: $cipher');
          throw Exception('Unknown cipher: $cipher');
        }
      } else {
        saveStream = streamDownload.transform(transformer);
      }
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
    ]).then((value) => finalize.complete(value));

    bool? saveResult;

    logger.i('Saving file...');

    final progressController = StreamController<double>();

    final subscription =
        _ardriveIo.saveFileStream(file, finalize).listen((saveStatus) {
      if (saveStatus.saveResult == null) {
        logger.d(
            'Saving file progress: ${saveStatus.bytesSaved} / ${saveStatus.totalBytes}');

        final progress = saveStatus.bytesSaved / saveStatus.totalBytes;

        logger.d('Saving file progress: ${progress * 100}%');

        progressController.sink.add(progress * 100);
      } else {
        saveResult = saveStatus.saveResult!;
      }
    });

    subscription.onDone(() async {
      if (_cancelWithReason.isCompleted) {
        logger.d('Download cancelled');

        throw Exception(
            'Download cancelled: ${await _cancelWithReason.future}');
      }

      if (saveResult != true) throw Exception('Failed to save file');

      logger.d('File saved');
    });

    subscription.onError((e) {
      logger.e(e);
    });

    return progressController.stream;
  }
}

final StreamTransformer<List<int>, Uint8List> transformer =
    StreamTransformer.fromHandlers(
  handleData: (List<int> data, EventSink<Uint8List> sink) {
    sink.add(Uint8List.fromList(data));
  },
);

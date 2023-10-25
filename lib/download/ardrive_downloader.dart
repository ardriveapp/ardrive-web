import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:arweave/arweave.dart' as arweave;
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart' hide Cipher;

abstract class ArDriveDownloader {
  Stream<double> downloadFile({
    required String dataTx,
    required int fileSize,
    required String fileName,
    required DateTime lastModifiedDate,
    required String contentType,
    Completer<String>? cancelWithReason,
    SecretKey? fileKey,
    String? cipher,
    String? cipherIvString,
  });

  factory ArDriveDownloader({
    required IOFileAdapter ioFileAdapter,
    required ArDriveIO ardriveIo,
  }) {
    return _ArDriveDownloader(ioFileAdapter, ardriveIo);
  }
}

class _ArDriveDownloader implements ArDriveDownloader {
  final IOFileAdapter _ioFileAdapter;
  final ArDriveIO _ardriveIo;

  _ArDriveDownloader(this._ioFileAdapter, this._ardriveIo);

  final Completer<String> _cancelWithReason = Completer<String>();

  final StreamController<LinearProgress> downloadProgressController =
      StreamController<LinearProgress>.broadcast();

  Stream<LinearProgress> get downloadProgress =>
      downloadProgressController.stream;

  @override
  Stream<double> downloadFile({
    required String dataTx,
    required int fileSize,
    required String fileName,
    required DateTime lastModifiedDate,
    required String contentType,
    Completer<String>? cancelWithReason,
    SecretKey? fileKey,
    String? cipher,
    String? cipherIvString,
  }) async* {
    final streamDownloadResponse = await arweave.download(
      txId: dataTx,
      onProgress: (progress, speed) => logger.d(progress.toString()),
    );

    final streamDownload = streamDownloadResponse.$1;

    Stream<Uint8List> saveStream;

    if (fileKey != null && cipher != null && cipherIvString != null) {
      final cipherIv = decodeBase64ToBytes(cipherIvString);

      final keyData = Uint8List.fromList(await fileKey.extractBytes());

      if (cipher == Cipher.aes256ctr) {
        saveStream = await decryptTransactionDataStream(
          cipher,
          cipherIv,
          streamDownload.transform(transformer),
          keyData,
          fileSize,
        );
      } else if (cipher == Cipher.aes256gcm) {
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
      } else {
        throw Exception('Unknown cipher: $cipher');
      }
    } else {
      saveStream = streamDownload.transform(transformer);
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

    await for (final saveStatus in _ardriveIo.saveFileStream(file, finalize)) {
      if (saveStatus.saveResult == null) {
        if (saveStatus.bytesSaved == 0) continue;

        final progress = saveStatus.bytesSaved / saveStatus.totalBytes;

        logger.d('Saving file progress: ${progress * 100}%');

        yield progress * 100;

        // final progressPercentInt = (progress * 100).round();
        // emit(FileDownloadWithProgress(
        //   fileName: _file.name,
        //   progress: progressPercentInt,
        //   fileSize: saveStatus.totalBytes,
        // ));
      } else {
        saveResult = saveStatus.saveResult!;
      }
    }

    logger.i('File saved');

    if (_cancelWithReason.isCompleted) {
      throw Exception('Download cancelled: ${await _cancelWithReason.future}');
    }
    if (saveResult != true) throw Exception('Failed to save file');
  }
}

final StreamTransformer<List<int>, Uint8List> transformer =
    StreamTransformer.fromHandlers(
  handleData: (List<int> data, EventSink<Uint8List> sink) {
    sink.add(Uint8List.fromList(data));
  },
);

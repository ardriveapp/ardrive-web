import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:dio/dio.dart';
import 'package:retry/retry.dart';
import 'package:ardrive_logger/ardrive_logger.dart';

final logger = Logger(
  logLevel: LogLevel.debug,
  storeLogsInMemory: true,
  logExporter: LogExporter(),
);

class TurboUploadService<Response> {
  TurboUploadService({
    required this.turboUploadUri,
  });

  final Uri turboUploadUri;
  final retry = RetryOptions(maxAttempts: 8);
  final CancelToken _cancelToken = CancelToken();

  Future<Response> post({
    required DataItemResult dataItem,
    required Wallet wallet,
    Function(double)? onSendProgress,
    required int size,
    required Map<String, dynamic> headers,
  }) async {
    logger.d('Uploading dataItem to Turbo');

    final dio = Dio();

    final uploadInfo = await retry.retry(
      () => dio.get('$turboUploadUri/chunks/arweave/-1/-1'),
    );
    final uploadId = uploadInfo.data['id'];
    final uploadChunkSizeMinInBytes = uploadInfo.data['min'];
    logger.d('Got upload info from Turbo');
    logger.d('Upload ID: $uploadId');
    logger.d('Upload chunk size: $uploadChunkSizeMinInBytes');

    final dataItemStream = dataItem.streamGenerator();

    Map<int, int> progressCounter = {};

    final maxUploadsInParallel = MiB(50).size ~/ uploadChunkSizeMinInBytes;
    logger.d('Max uploads in parallel: $maxUploadsInParallel');

    if (onSendProgress != null) {
      Timer.periodic(Duration(milliseconds: 500), (timer) {
        final progress = progressCounter.values.reduce((a, b) => a + b);
        onSendProgress(progress / size);
      });
    }

    await _processStream(
        dataItemStream, uploadChunkSizeMinInBytes, maxUploadsInParallel,
        (chunk, offset) async {
      try {
        logger.d('Uploading chunk. Offset: $offset');
        return retry.retry(
          () => dio.post(
            '$turboUploadUri/chunks/arweave/$uploadId/$offset',
            data: chunk,
            onSendProgress: (sent, _) {
              if (onSendProgress != null) {
                progressCounter[offset] = sent;
              }
            },
            options: Options(
              headers: {
                'Content-Type': 'application/octet-stream',
                'Content-Length': chunk.length.toString(),
              }..addAll(headers),
            ),
          ),
        );
      } catch (e) {
        if (_isCanceled) {
          logger.d('Upload canceled');
          _cancelToken.cancel();
        }
        rethrow;
      }
    });

    try {
      logger.d('Finalising upload');
      final finaliseInfo = await retry.retry(
        () => dio.post(
          '$turboUploadUri/chunks/arweave/$uploadId/-1',
          data: null,
        ),
      );
      logger.d('Upload finalised');

      return finaliseInfo as Response;
    } catch (e) {
      if (_isCanceled) {
        logger.d('Upload canceled');
        _cancelToken.cancel();
      }
      rethrow;
    }
  }

  Future<void> cancel() {
    _cancelToken.cancel();
    print('Stream closed');
    _isCanceled = true;
    return Future.value();
  }

  bool _isCanceled = false;

  Future<void> _processStream(
    Stream<Uint8List> stream,
    int chunkSize,
    int maxConcurrent,
    Future<dynamic> Function(Uint8List, int) processChunk,
  ) async {
    final chunkedStream = streamToChunks(stream, chunkSize);
    final runningTasks = <Future>[];
    int offset = 0;

    await for (final chunk in chunkedStream) {
      if (runningTasks.length >= maxConcurrent) {
        logger.d('Waiting for a task to finish');
        await Future.any(runningTasks);
      }

      logger.d('Starting new task. Offset: $offset');
      final task = processChunk(chunk, offset);
      task.whenComplete(() {
        logger.d('Task completed. Offset: $offset');
        runningTasks.remove(task);
      });

      runningTasks.add(task);

      offset += chunk.length;
    }

    logger.d('Waiting for all tasks to finish');
    await Future.wait(runningTasks);
  }
}

class TurboUploadExceptions implements Exception {}

class TurboUploadTimeoutException implements TurboUploadExceptions {}

Stream<Uint8List> streamToChunks(
    Stream<Uint8List> stream, int chunkSize) async* {
  var buffer = BytesBuilder();

  await for (var uint8list in stream) {
    buffer.add(uint8list);

    while (buffer.length >= chunkSize) {
      final currentBytes = buffer.takeBytes();
      yield Uint8List.fromList(currentBytes.sublist(0, chunkSize));

      buffer.add(currentBytes.sublist(chunkSize));
    }
  }

  if (buffer.length > 0) {
    yield buffer.toBytes();
  }
}

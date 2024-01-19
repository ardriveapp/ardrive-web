import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:dio/dio.dart';
import 'package:retry/retry.dart';
import 'package:ardrive_uploader/src/utils/logger.dart';

class TurboUploadService {
  TurboUploadService({
    required this.turboUploadUri,
  });

  final Uri turboUploadUri;
  final r = RetryOptions(maxAttempts: 8);
  final CancelToken _cancelToken = CancelToken();

  Future<Response> post({
    required DataItemResult dataItem,
    required Wallet wallet,
    Function(double)? onSendProgress,
    Map<String, dynamic>? headers,
  }) async {
    logger.d('Uploading dataItem to Turbo');

    final dio = Dio();

    final uploadInfo = await r.retry(
      () => dio.get('$turboUploadUri/chunks/arweave/-1/-1'),
    );
    final uploadId = uploadInfo.data['id'] as String;
    final uploadChunkSizeMinInBytes = uploadInfo.data['min'] as int;
    logger.d('Got upload info from Turbo');
    logger.d('Upload ID: $uploadId');
    logger.d('Upload chunk size: $uploadChunkSizeMinInBytes');

    // (offset: sent bytes) map for in flight requests progress
    Map<int, int> inFlightRequestsBytesSent = {};
    int completedRequestsBytesSent = 0;

    final maxUploadsInParallel = MiB(50).size ~/ uploadChunkSizeMinInBytes;
    logger.d('Max uploads in parallel: $maxUploadsInParallel');

    if (onSendProgress != null) {
      Timer.periodic(Duration(milliseconds: 500), (timer) {
        final inFlightBytesSent = inFlightRequestsBytesSent.isEmpty
            ? 0
            : inFlightRequestsBytesSent.values.reduce((a, b) => a + b);
        final totalBytesSent = completedRequestsBytesSent + inFlightBytesSent;
        final progress = totalBytesSent / dataItem.dataItemSize;

        if (progress == 1) {
          timer.cancel();
        }

        onSendProgress(totalBytesSent / dataItem.dataItemSize);
      });
    }

    await _processStream(
        stream: dataItem.streamGenerator(),
        chunkSize: uploadChunkSizeMinInBytes,
        maxConcurrent: maxUploadsInParallel, (chunk, offset) async {
      try {
        logger.d('Uploading chunk. Offset: $offset');
        return r.retry(
          () => dio.post(
            '$turboUploadUri/chunks/arweave/$uploadId/$offset',
            data: chunk,
            onSendProgress: (sent, _) {
              if (onSendProgress != null) {
                inFlightRequestsBytesSent[offset] = sent;
              }
            },
            options: Options(
              headers: {
                'Content-Type': 'application/octet-stream',
                'Content-Length': chunk.length.toString(),
              }..addAll(headers ?? const {}),
            ),
            cancelToken: _cancelToken,
          )..whenComplete(() {
              if (onSendProgress != null) {
                inFlightRequestsBytesSent.remove(offset);
                completedRequestsBytesSent += chunk.length;
              }
            }),
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
      final finaliseInfo = await r.retry(
        () => dio.post(
          '$turboUploadUri/chunks/arweave/$uploadId/-1',
          data: null,
          cancelToken: _cancelToken,
        ),
      );
      logger.d('Upload finalised');

      return finaliseInfo;
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
    logger.d('Stream closed');
    _isCanceled = true;
    return Future.value();
  }

  bool _isCanceled = false;

  Future<void> _processStream(
    Future<dynamic> Function(Uint8List, int) processChunk, {
    required Stream<Uint8List> stream,
    required int chunkSize,
    required int maxConcurrent,
  }) async {
    logger.d('Processing DataItem stream');
    final chunkedStream = streamToChunks(stream, chunkSize);
    logger.d('Stream chunked');
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

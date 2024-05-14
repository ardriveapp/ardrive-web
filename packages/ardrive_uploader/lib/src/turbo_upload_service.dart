import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:ardrive_uploader/src/exceptions.dart';
import 'package:ardrive_uploader/src/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:dio/dio.dart';
import 'package:retry/retry.dart';

class TurboUploadService {
  TurboUploadService({
    required this.turboUploadUri,
  });

  final Uri turboUploadUri;
  final r = RetryOptions(maxAttempts: 8);
  final List<CancelToken> _cancelTokens = [];
  final dio = Dio();
  final maxInFlightData = MiB(100).size;
  Timer? onSendProgressTimer;

  Future<Response> post({
    required DataItemResult dataItem,
    required Wallet wallet,
    Function(double)? onSendProgress,
    Map<String, dynamic>? headers,
  }) async {
    logger.d('[${dataItem.id}] Uploading DataItem to Turbo');

    final uploadInfo = await r.retry(
      () => dio.get('$turboUploadUri/chunks/arweave/-1/-1'),
    );

    final uploadId = uploadInfo.data['id'] as String;
    final uploadChunkSizeMinInBytes = uploadInfo.data['min'] as int;
    final uploadChunkSizeMaxInBytes = uploadInfo.data['max'] as int;
    final uploadChunkSizeInBytes = _calculateChunkSize(
      dataSize: dataItem.dataItemSize,
      minChunkSize: uploadChunkSizeMinInBytes,
      maxChunkSize: uploadChunkSizeMaxInBytes,
    );
    final maxUploadsInParallel = maxInFlightData ~/ uploadChunkSizeInBytes;
    logger.i(
        '[${dataItem.id}] Upload ID: $uploadId, Uploads in parallel: $maxUploadsInParallel, Chunk size: $uploadChunkSizeInBytes');

    // (offset: sent bytes) map for in flight requests progress
    Map<int, int> inFlightRequestsBytesSent = {};
    int completedRequestsBytesSent = 0;

    if (onSendProgress != null) {
      onSendProgressTimer =
          Timer.periodic(Duration(milliseconds: 500), (timer) {
        final inFlightBytesSent = inFlightRequestsBytesSent.isEmpty
            ? 0
            : inFlightRequestsBytesSent.values.reduce((a, b) => a + b);
        final totalBytesSent = completedRequestsBytesSent + inFlightBytesSent;
        final progress = totalBytesSent / dataItem.dataItemSize;

        if (progress >= 1) {
          timer.cancel();
        }

        onSendProgress(totalBytesSent / dataItem.dataItemSize);
      });
    }

    await _processStream(
        stream: dataItem.streamGenerator(),
        chunkSize: uploadChunkSizeInBytes,
        maxConcurrent: maxUploadsInParallel,
        dataItemId: dataItem.id, (chunk, offset) async {
      if (_isCanceled) {
        throw UploadCanceledException('Upload canceled. Cant upload chunk.');
      }

      final cancelToken = CancelToken();

      _cancelTokens.add(cancelToken);

      try {
        logger.d('[${dataItem.id}] Uploading chunk. Offset: $offset');
        return r.retry(() {
          return dio.post(
            '$turboUploadUri/chunks/arweave/$uploadId/$offset',
            data: chunk,
            onSendProgress: (sent, total) {
              if (onSendProgress != null) {
                if (inFlightRequestsBytesSent[offset] == null) {
                  inFlightRequestsBytesSent[offset] = 0;
                } else if (inFlightRequestsBytesSent[offset]! < sent) {
                  inFlightRequestsBytesSent[offset] = sent;
                }
              }
            },
            options: Options(
              headers: {
                'Content-Type': 'application/octet-stream',
                'Content-Length': chunk.length.toString(),
              }..addAll(headers ?? const {}),
            ),
            cancelToken: cancelToken,
          );
        }).then((response) {
          _cancelTokens.remove(cancelToken);

          if (onSendProgress != null) {
            inFlightRequestsBytesSent.remove(offset);
            completedRequestsBytesSent += chunk.length;
          }

          return response;
        }, onError: (error) {
          onSendProgressTimer?.cancel();
          _cancelTokens.remove(cancelToken);
          throw error;
        });
      } catch (e) {
        if (_isCanceled) {
          logger.i('[${dataItem.id}] Upload canceled');
          onSendProgressTimer?.cancel();
          cancelToken.cancel();
        }

        _cancelTokens.remove(cancelToken);

        rethrow;
      }
    });

    final finalizeCancelToken = CancelToken();

    try {
      logger.i('[${dataItem.id}] Finalising upload to Turbo');

      _cancelTokens.add(finalizeCancelToken);

      final finaliseInfo = await r.retry(
        () => dio.post(
          '$turboUploadUri/chunks/arweave/$uploadId/finalize',
          data: null,
          cancelToken: finalizeCancelToken,
        ),
      );

      if (finaliseInfo.statusCode == 202) {
        // TODO: Send this upload to a queue. We'd need to change the
        // type of the returned data though. Perhaps the returned object
        // could be an event emitter that the calling client can use to
        // listen for async outcomes like finalization success/failure.
        final confirmInfo = await _confirmUpload(
          dataItemId: dataItem.id,
          uploadId: uploadId,
          dataItemSize: dataItem.dataItemSize,
        );

        onSendProgressTimer?.cancel();

        return confirmInfo;
      }

      logger.i('[${dataItem.id}] Upload finalised');

      onSendProgressTimer?.cancel();

      return finaliseInfo;
    } catch (e) {
      if (e is DioException) {
        logger.i('[${dataItem.id}] Finalising upload failed, ${e.type}');
      } else if (_isCanceled) {
        logger.i('[${dataItem.id}] Upload canceled');
        finalizeCancelToken.cancel();
      }

      onSendProgressTimer?.cancel();

      rethrow;
    }
  }

  // TODO: This funciton as designed should go away, but some incremental
  // improvements that could be helpful:
  // - Don't use recursion. Use a while loop instead.
  // - Have a max retry count and/or max finalization time
  // - Make retries based on an exponential backoff rather than a fixed delay
  // - Make starting time for first wait based on some linear function of file size
  // - Don't keep retrying infinitely in the case of errors.
  Future<Response> _confirmUpload({
    required TxID dataItemId,
    required String uploadId,
    required int dataItemSize,
  }) async {
    final fileSizeInGiB = (dataItemSize.toDouble() / GiB(1).size).ceil();
    final maxWaitTime = Duration(minutes: fileSizeInGiB);
    logger.d(
        '[$dataItemId] Confirming upload to Turbo with uploadId $uploadId for up to ${maxWaitTime.inMinutes} minutes.');

    final startTime = DateTime.now();
    final cutoffTime = startTime.add(maxWaitTime);
    int attemptCount = 0;

    while (DateTime.now().isBefore(cutoffTime)) {
      final response = await dio.get(
        '$turboUploadUri/chunks/arweave/$uploadId/status',
      );

      final responseData = response.data;
      final responseStatus = responseData['status'];
      switch (responseStatus) {
        case 'FINALIZED':
          logger.i('[$dataItemId] DataItem confirmed!');
          return response;
        case 'UNDERFUNDED':
          throw UploadCanceledException('Upload canceled. Underfunded.');
        case 'ASSEMBLING':
        case 'VALIDATING':
        case 'FINALIZING':
          final retryAfterDuration =
              dataItemConfirmationRetryDelay(attemptCount++);
          logger.i(
              '[$dataItemId] DataItem not confirmed. Retrying in ${retryAfterDuration.inMilliseconds}ms');

          await Future.delayed(retryAfterDuration);
        default:
          throw UploadCanceledException(
              'Upload canceled. Finalization failed. Status: ${responseData['status']}');
      }
    }
    throw UploadCanceledException(
        'Upload canceled. Finalization took too long.');
  }

  Future<void> cancel() {
    logger.d('Stream closed');

    for (var cancelToken in _cancelTokens) {
      cancelToken.cancel();
    }

    _isCanceled = true;
    onSendProgressTimer?.cancel();
    return Future.value();
  }

  bool _isCanceled = false;

  int _calculateChunkSize({
    required int dataSize,
    required int minChunkSize,
    required int maxChunkSize,
  }) {
    getValidChunkSize(int chunkSize) {
      if (chunkSize < minChunkSize) {
        return minChunkSize;
      } else if (chunkSize > maxChunkSize) {
        return maxChunkSize;
      } else {
        return chunkSize;
      }
    }

    if (dataSize < GiB(1).size) {
      return getValidChunkSize(MiB(5).size);
    } else if (dataSize <= GiB(2).size) {
      return getValidChunkSize(MiB(25).size);
    } else {
      return getValidChunkSize(MiB(50).size);
    }
  }

  Future<void> _processStream(
    Future<dynamic> Function(Uint8List, int) processChunk, {
    required Stream<Uint8List> stream,
    required int chunkSize,
    required int maxConcurrent,
    required TxID dataItemId,
  }) async {
    logger.d('[$dataItemId] Processing DataItem stream');
    final chunkedStream = streamToChunks(stream, chunkSize);
    logger.d('[$dataItemId] Stream chunked');
    final runningTasks = <Future>[];
    int offset = 0;

    await for (final chunk in chunkedStream) {
      if (runningTasks.length >= maxConcurrent) {
        logger.d('[$dataItemId] Waiting for a task to finish');
        await Future.any(runningTasks);
      }

      logger.d('[$dataItemId] Starting new task. Offset: $offset');
      final task = processChunk(chunk, offset);
      task.whenComplete(() {
        logger.d('[$dataItemId] Task completed. Offset: $offset');
        runningTasks.remove(task);
      });

      runningTasks.add(task);

      offset += chunk.length;
    }

    logger.d('[$dataItemId] Waiting for all tasks to finish');
    await Future.wait(runningTasks);
  }
}

Stream<Uint8List> streamToChunks(
  Stream<Uint8List> stream,
  int chunkSize,
) async* {
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

final defaultBaseDuration = Duration(milliseconds: 250);

Duration dataItemConfirmationRetryDelay(
  int iteration, {
  Duration baseDuration = const Duration(milliseconds: 100),
  Duration maxDuration = const Duration(seconds: 8),
}) {
  return Duration(
    milliseconds: min(
      baseDuration.inMilliseconds * pow(2, iteration).toInt(),
      maxDuration.inMilliseconds,
    ),
  );
}

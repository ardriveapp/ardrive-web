import 'dart:async';
import 'dart:typed_data';

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
  final CancelToken _cancelToken = CancelToken();
  final dio = Dio();
  final dataItemConfirmationRetryDelay = Duration(seconds: 15);
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
    logger.d(
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
      try {
        logger.d('[${dataItem.id}] Uploading chunk. Offset: $offset');
        return r
            .retry(() => dio.post(
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
                  cancelToken: _cancelToken,
                ))
            .then((response) {
          if (onSendProgress != null) {
            inFlightRequestsBytesSent.remove(offset);
            completedRequestsBytesSent += chunk.length;
          }
          return response;
        }, onError: (error) {
          onSendProgressTimer?.cancel();
          throw error;
        });
      } catch (e) {
        if (_isCanceled) {
          logger.d('[${dataItem.id}] Upload canceled');
          onSendProgressTimer?.cancel();
          _cancelToken.cancel();
        }

        rethrow;
      }
    });

    try {
      logger.d('[${dataItem.id}] Finalising upload to Turbo');
      final finaliseInfo = await r.retry(
        () => dio.post(
          '$turboUploadUri/chunks/arweave/$uploadId/-1',
          data: null,
          cancelToken: _cancelToken,
          options: Options(
            validateStatus: (int? status) {
              return status != null &&
                  ((status >= 200 && status < 300) || status == 504);
            },
          ),
        ),
      );

      if (finaliseInfo.statusCode == 504) {
        final confirmInfo = await _confirmUpload(dataItem.id);
        onSendProgressTimer?.cancel();

        return confirmInfo;
      }

      logger.d('[${dataItem.id}] Upload finalised');

      onSendProgressTimer?.cancel();

      return finaliseInfo;
    } catch (e) {
      if (e is DioException) {
        logger.d('[${dataItem.id}] Finalising upload failed, ${e.type}');
      } else if (_isCanceled) {
        logger.d('[${dataItem.id}] Upload canceled');
        _cancelToken.cancel();
      }

      onSendProgressTimer?.cancel();

      rethrow;
    }
  }

  Future<Response> _confirmUpload(TxID dataItemId) async {
    try {
      logger.d('[$dataItemId] Confirming upload to Turbo');
      final response = await dio.get(
        '$turboUploadUri/v1/tx/$dataItemId/status',
      );

      final responseData = response.data;

      if (responseData['status'] == 'CONFIRMED' ||
          responseData['status'] == 'FINALIZED') {
        logger.d('[$dataItemId] DataItem confirmed!');
        return response;
      } else {
        logger.d(
            '[$dataItemId] DataItem not confirmed. Retrying in ${dataItemConfirmationRetryDelay.toString()}');

        await Future.delayed(dataItemConfirmationRetryDelay);

        return _confirmUpload(dataItemId);
      }
    } catch (e) {
      await Future.delayed(dataItemConfirmationRetryDelay);

      return _confirmUpload(dataItemId);
    }
  }

  Future<void> cancel() {
    logger.d('Stream closed');
    _cancelToken.cancel();
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

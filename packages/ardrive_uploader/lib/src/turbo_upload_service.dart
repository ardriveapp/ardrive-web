import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:ardrive_uploader/src/exceptions.dart';
import 'package:ardrive_uploader/src/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:dio/dio.dart';
import 'package:retry/retry.dart';

abstract class TurboUploadService {
  Future<Response> post({
    required DataItemResult dataItem,
    required Wallet wallet,
    Function(double)? onSendProgress,
    Map<String, dynamic>? headers,
  });

  Future<void> cancel();
}

abstract class TurboUploadServiceChunkUploadsBase
    implements TurboUploadService {
  TurboUploadServiceChunkUploadsBase(this.turboUploadUri);

  final Uri turboUploadUri;
  final r = RetryOptions(maxAttempts: 8);
  final List<CancelToken> _cancelTokens = [];
  final dio = Dio();
  Timer? onSendProgressTimer;
  bool _isCanceled = false;

  @override
  Future<Response> post({
    required DataItemResult dataItem,
    required Wallet wallet,
    Function(double)? onSendProgress,
    Map<String, dynamic>? headers,
  }) async {
    logger.d('[${dataItem.id}] Starting upload...');

    // 1) Fetch basic upload info
    final uploadInfo = await r.retry(
      () => dio.get('$turboUploadUri/chunks/arweave/-1/-1'),
    );
    final uploadId = uploadInfo.data['id'] as String;
    final minChunkSize = uploadInfo.data['min'] as int;
    final maxChunkSize = uploadInfo.data['max'] as int;

    // 2) Calculate chunk size + concurrency
    final chunkSize = _calculateChunkSize(
      dataSize: dataItem.dataItemSize,
      minChunkSize: minChunkSize,
      maxChunkSize: maxChunkSize,
    );
    final maxInFlightData = MiB(100).size;
    final maxUploadsInParallel = maxInFlightData ~/ chunkSize;

    logger.d(
      '[${dataItem.id}] UploadID=$uploadId, chunkSize=$chunkSize, parallel=$maxUploadsInParallel',
    );

    // Setup for progress tracking
    Map<int, int> inFlightRequestsBytesSent = {};
    int completedRequestsBytesSent = 0;
    if (onSendProgress != null) {
      onSendProgressTimer = Timer.periodic(Duration(milliseconds: 500), (_) {
        if (inFlightRequestsBytesSent.isEmpty) return;

        final inFlightSum =
            inFlightRequestsBytesSent.values.fold(0, (a, b) => a + b);
        final totalBytesSent = completedRequestsBytesSent + inFlightSum;
        final progress = totalBytesSent / dataItem.dataItemSize;
        onSendProgress(progress);

        // If we reached 100%, cancel the timer
        if (progress >= 1.0) {
          onSendProgressTimer?.cancel();
        }
      });
    }

    // 3) Stream and upload chunks concurrently
    await _processStream(
      stream: dataItem.streamGenerator(),
      chunkSize: chunkSize,
      maxConcurrent: maxUploadsInParallel,
      dataItemId: dataItem.id,
      processChunk: (chunk, offset) async {
        if (_isCanceled) {
          throw UploadCanceledException('Upload canceled');
        }

        final cancelToken = CancelToken();
        _cancelTokens.add(cancelToken);

        try {
          final response = await r
              .retry(() => _uploadChunkRequest(
                    uploadId: uploadId,
                    chunk: chunk,
                    offset: offset,
                    headers: headers ?? const {},
                    onSendProgress: (sent) {
                      if (onSendProgress == null) return;
                      inFlightRequestsBytesSent[offset] =
                          max(inFlightRequestsBytesSent[offset] ?? 0, sent);
                    },
                    cancelToken: cancelToken,
                  ))
              .then(
            (response) {
              // On success
              _cancelTokens.remove(cancelToken);
              if (onSendProgress != null) {
                // Once chunk is fully uploaded, move to "completed"
                final uploadedThisChunk =
                    inFlightRequestsBytesSent[offset] ?? chunk.length;
                completedRequestsBytesSent += uploadedThisChunk;
                inFlightRequestsBytesSent.remove(offset);
              }
              return response;
            },
            onError: (err) {
              // On error
              onSendProgressTimer?.cancel();
              _cancelTokens.remove(cancelToken);
              throw err;
            },
          );

          return response;
        } catch (err) {
          if (_isCanceled) {
            cancelToken.cancel();
            onSendProgressTimer?.cancel();
          }
          _cancelTokens.remove(cancelToken);
          rethrow;
        }
      },
    );

    // 4) Finalize upload
    try {
      logger.d('[${dataItem.id}] Finalizing upload: $uploadId');
      final finalizeResponse = await finalizeUpload(
        uploadId: uploadId,
        dataItemSize: dataItem.dataItemSize,
        dataItemId: dataItem.id,
        headers: headers ?? const {},
      );
      onSendProgressTimer?.cancel();
      return finalizeResponse;
    } catch (err) {
      onSendProgressTimer?.cancel();
      rethrow;
    }
  }

  Future<Response> finalizeUpload({
    required String uploadId,
    required int dataItemSize,
    required TxID dataItemId,
    required Map<String, dynamic> headers,
  });

  Future<Response> _uploadChunkRequest({
    required String uploadId,
    required Uint8List chunk,
    required int offset,
    required Map<String, dynamic> headers,
    required Function(int) onSendProgress,
    required CancelToken cancelToken,
  });

  @override
  Future<void> cancel() async {
    _isCanceled = true;
    onSendProgressTimer?.cancel();
    for (final token in _cancelTokens) {
      token.cancel();
    }
    logger.d('Upload canceled.');
  }
}

/// A small helper to process a stream in fixed-size chunks concurrently.
Future<void> _processStream({
  required Future<dynamic> Function(Uint8List, int) processChunk,
  required Stream<Uint8List> stream,
  required int chunkSize,
  required int maxConcurrent,
  required TxID dataItemId,
}) async {
  logger.d('[$dataItemId] Processing DataItem stream');
  final chunkedStream = streamToChunks(stream, chunkSize);

  final runningTasks = <Future>[];
  int offset = 0;

  await for (final chunk in chunkedStream) {
    if (runningTasks.length >= maxConcurrent) {
      await Future.any(runningTasks);
    }

    final task = processChunk(chunk, offset);
    runningTasks.add(task);
    task.whenComplete(() => runningTasks.remove(task));

    offset += chunk.length;
  }

  await Future.wait(runningTasks);
  logger.d('[$dataItemId] All chunks uploaded');
}

/// Converts the stream into fixed-size chunks
Stream<Uint8List> streamToChunks(
    Stream<Uint8List> stream, int chunkSize) async* {
  final buffer = BytesBuilder();
  await for (final data in stream) {
    buffer.add(data);
    while (buffer.length >= chunkSize) {
      final currentBytes = buffer.takeBytes();
      yield Uint8List.fromList(currentBytes.sublist(0, chunkSize));
      buffer.add(currentBytes.sublist(chunkSize));
    }
  }
  if (buffer.isNotEmpty) {
    yield buffer.toBytes();
  }
}

/// Calculates a valid chunk size based on the total data size
int _calculateChunkSize({
  required int dataSize,
  required int minChunkSize,
  required int maxChunkSize,
}) {
  int applyLimits(int c) =>
      c < minChunkSize ? minChunkSize : (c > maxChunkSize ? maxChunkSize : c);

  if (dataSize < GiB(1).size) {
    return applyLimits(MiB(5).size);
  } else if (dataSize <= GiB(2).size) {
    return applyLimits(MiB(25).size);
  } else {
    return applyLimits(MiB(50).size);
  }
}

class TurboUploadServiceMultipart extends TurboUploadServiceChunkUploadsBase {
  TurboUploadServiceMultipart({required Uri turboUploadUri})
      : super(turboUploadUri);

  @override
  Future<Response> finalizeUpload({
    required String uploadId,
    required int dataItemSize,
    required TxID dataItemId,
    required Map<String, dynamic> headers,
  }) async {
    try {
      // POST /finalize
      final finalizeResponse = await r.retry(
        () => dio.post(
          '$turboUploadUri/chunks/arweave/$uploadId/finalize',
          options: Options(
            headers: headers,
          ),
        ),
      );

      // If the server returns 202 (still assembling/finalizing), you could poll
      // for status, like in your original _confirmUpload method. For brevity,
      // you might just return it here or do something like:
      if (finalizeResponse.statusCode == 202) {
        logger.i('Still finalizing. Checking status...');
        return _confirmUpload(
          dataItemId: dataItemId,
          uploadId: uploadId,
          dataItemSize: dataItemSize,
        );
      }

      logger.i('Multipart finalize complete.');
      return finalizeResponse;
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<Response> _uploadChunkRequest({
    required String uploadId,
    required Uint8List chunk,
    required int offset,
    required Map<String, dynamic> headers,
    required Function(int) onSendProgress,
    required CancelToken cancelToken,
  }) async {
    // POST /{uploadId}/{offset}
    return dio.post(
      '$turboUploadUri/chunks/arweave/$uploadId/$offset',
      data: chunk,
      onSendProgress: (sent, total) => onSendProgress(sent.toInt()),
      options: Options(
        headers: {
          'Content-Type': 'application/octet-stream',
          'Content-Length': chunk.length.toString(),
          ...headers,
        },
      ),
      cancelToken: cancelToken,
    );
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
          throw UnderFundException(
              message: 'Upload canceled. Underfunded.', error: response.data);
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
}

class TurboUploadServiceNonChunked extends TurboUploadService {
  TurboUploadServiceNonChunked(this.turboUploadUri) : super();

  final Uri turboUploadUri;
  final r = RetryOptions(maxAttempts: 8);
  final dio = Dio();
  Timer? onSendProgressTimer;
  final cancelToken = CancelToken();
  final TabVisibilitySingleton _tabVisibility = TabVisibilitySingleton();

  @override
  Future<void> cancel() {
    onSendProgressTimer?.cancel();
    cancelToken.cancel();
    return Future.value();
  }

  @override
  Future<Response> post({
    required DataItemResult dataItem,
    required Wallet wallet,
    Function(double p1)? onSendProgress,
    Map<String, dynamic>? headers,
  }) async {
    final controller = StreamController<double>();

    controller.add(0);
    try {
      final acceptedStatusCodes = [200, 202, 204];

      final url = '$turboUploadUri/v1/tx';
      const receiveTimeout = Duration(days: 365);
      const sendTimeout = Duration(days: 365);

      final response = await dio.post(
        url,
        onSendProgress: (sent, total) => onSendProgress?.call(sent / total),
        data: dataItem.streamGenerator(),
        options: Options(
          headers: headers ?? const {},
          receiveTimeout: receiveTimeout,
          sendTimeout: sendTimeout,
        ),
        cancelToken: cancelToken,
      );

      if (!acceptedStatusCodes.contains(response.statusCode)) {
        logger.e('Error posting bytes', response.data);
        throw Exception('Error posting bytes');
      }

      if (!acceptedStatusCodes.contains(response.statusCode)) {
        logger.e('Error posting bytes', response.data);
        throw _handleException(response);
      }

      return response;
    } catch (e, stacktrace) {
      logger.e('Catching error in postDataItem', e, stacktrace);
      throw _handleException(e);
    }
  }

  Exception _handleException(Object error) {
    logger.e('Handling exception in UploadService', error);

    if (error is DioException && error.response?.statusCode == 408) {
      logger.e(
        'Handling exception in UploadService with status code: ${error.response?.statusCode}',
        error,
      );

      return TurboUploadTimeoutException();
    }

    return Exception(error);
  }
}

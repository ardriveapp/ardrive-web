import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:dio/dio.dart';
import 'package:retry/retry.dart';

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
    final dio = Dio();

    final uploadInfo = await retry.retry(
      () => dio.get('$turboUploadUri/chunks/arweave/-1/-1'),
    );
    final uploadId = uploadInfo.data['id'];
    final uploadChunkSizeMin = uploadInfo.data['min'];

    final dataItemStream = dataItem.streamGenerator();

    Map<int, int> progressCounter = {};

    final maxUploadsInParallel = MiB(50).size ~/ uploadChunkSizeMin;

    if (onSendProgress != null) {
      Timer.periodic(Duration(milliseconds: 500), (timer) {
        final progress = progressCounter.values.reduce((a, b) => a + b);
        onSendProgress(progress / size);
      });
    }

    await _processStream(
        dataItemStream, uploadChunkSizeMin, maxUploadsInParallel,
        (chunk, offset) async {
      try {
        return retry.retry(
          () => dio.post(
            '$turboUploadUri/chunks/arweave/$uploadId/$offset',
            data: chunk,
            onSendProgress: (sent, total) {
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
          _cancelToken.cancel();
        }
        rethrow;
      }
    });

    try {
      final finaliseInfo = await retry.retry(
        () => dio.post(
          '$turboUploadUri/chunks/arweave/$uploadId/-1',
          data: null,
        ),
      );
      return finaliseInfo as Response;
    } catch (e) {
      if (_isCanceled) {
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
    Uint8List buffer = Uint8List(0);
    int offset = 0;
    List<Future> activeTasks = [];

    late StreamSubscription<Uint8List> subscription;
    Completer<void> done = Completer();

    subscription = stream.listen(
      (Uint8List data) {
        buffer = Uint8List.fromList(buffer + data);

        while (buffer.length >= chunkSize) {
          Uint8List chunk = Uint8List.sublistView(buffer, 0, chunkSize);
          final task = processChunk(chunk, offset);

          activeTasks.add(task);

          task.whenComplete(() {
            activeTasks.remove(task);
            if (activeTasks.length < maxConcurrent) {
              subscription.resume();
            }
          });

          offset += chunkSize;

          buffer = Uint8List.sublistView(buffer, chunkSize);

          if (activeTasks.length >= maxConcurrent) {
            subscription.pause();
          }
        }
      },
      onDone: () async {
        if (buffer.isNotEmpty) {
          activeTasks.add(processChunk(buffer, offset));
        }

        if (activeTasks.isNotEmpty) {
          await Future.wait(activeTasks);
        }

        done.complete();
      },
      onError: (e) {
        if (!done.isCompleted) {
          done.completeError(e);
        }
      },
      cancelOnError: true,
    );

    return done.future;
  }

  // retry(getCommunityContract, {required maxAttempts}) {}
}

class TurboUploadExceptions implements Exception {}

class TurboUploadTimeoutException implements TurboUploadExceptions {}

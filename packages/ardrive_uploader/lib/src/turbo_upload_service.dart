import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:dio/dio.dart';
import 'package:fetch_client/fetch_client.dart';
import 'package:http/http.dart' as http;

class TurboUploadService {
  final Uri turboUploadUri;

  /// We are using Dio directly here. In the future we must adapt our ArDriveHTTP to support
  /// streaming uploads.
  // ArDriveHTTP httpClient;

  TurboUploadService({
    required this.turboUploadUri,
  });

  /// We are using Dio directly here. In the future we must adapt our ArDriveHTTP to support
  /// streaming uploads.
  /// This is a temporary solution.
  Future<Response> postStream({
    required DataItemResult dataItem,
    required Wallet wallet,
    Function(double)? onSendProgress,
    required int size,
    required Map<String, dynamic> headers,
  }) async {
    final url = '$turboUploadUri/v1/tx';

    int dataItemSize = 0;

    await for (final data in dataItem.streamGenerator()) {
      size += data.length;
    }

    final dio = Dio();

    final response = await dio.post(
      url,
      onSendProgress: (sent, total) {
        onSendProgress?.call(sent / total);
      },
      data: dataItem.streamGenerator(), // Creates a Stream<List<int>>.
      options: Options(
        headers: {
          // stream
          Headers.contentTypeHeader: 'application/octet-stream',
          Headers.contentLengthHeader: size, // Set the content-length.
        }..addAll(headers),
      ),
    );

    print('Response from turbo: ${response.statusCode}');

    return response;
  }

  Future<FetchResponse> uploadStreamWithFetchClient({
    required DataItemResult dataItem,
    required Wallet wallet,
    Function(double)? onSendProgress,
    required int size,
    required Map<String, dynamic> headers,
  }) async {
    final url = '$turboUploadUri/v1/tx';

    int dataItemSize = 0;

    await for (final data in dataItem.streamGenerator()) {
      dataItemSize += data.length;
    }

    int uploaded = 0;

    StreamTransformer<Uint8List, Uint8List> createPassthroughTransformer() {
      return StreamTransformer.fromHandlers(
        handleData: (Uint8List data, EventSink<Uint8List> sink) {
          sink.add(data);
          uploaded += data.length;
          onSendProgress?.call(uploaded / dataItemSize);
          print('Uploaded: $uploaded / $dataItemSize');
        },
        handleError: (Object error, StackTrace stackTrace, EventSink sink) {
          sink.addError(error, stackTrace);
        },
        handleDone: (EventSink sink) {
          sink.close();
        },
      );
    }

    final client = FetchClient(
      mode: RequestMode.cors,
      streamRequests: true,
      cache: RequestCache.noCache,
    );

    final controller = StreamController<List<int>>(sync: false);

    final request = ArDriveStreamedRequest(
      'POST',
      Uri.parse(url),
      controller,
    )..headers.addAll({
        'content-type': 'application/octet-stream',
      });

    controller
        .addStream(
      dataItem.streamGenerator().transform(
            createPassthroughTransformer(),
          ),
    )
        .then((value) {
      print('Done');
      request.sink.close();
    });

    controller.onPause = () {
      print('Paused');
    };

    controller.onResume = () {
      print('Resumed');
    };

    request.contentLength = dataItemSize;

    final response = await client.send(request);

    print(await utf8.decodeStream(response.stream));

    return response;
  }
}

class TurboUploadExceptions implements Exception {}

class TurboUploadTimeoutException implements TurboUploadExceptions {}

class ArDriveStreamedRequest extends http.BaseRequest {
  /// The sink to which to write data that will be sent as the request body.
  ///
  /// This may be safely written to before the request is sent; the data will be
  /// buffered.
  ///
  /// Closing this signals the end of the request.
  EventSink<List<int>> get sink => _controller.sink;

  /// The controller for [sink], from which [BaseRequest] will read data for
  /// [finalize].
  final StreamController<List<int>> _controller;

  /// Creates a new streaming request.
  ArDriveStreamedRequest(
      String method, Uri url, StreamController<List<int>> controller)
      : _controller = controller,
        super(method, url);

  /// Freezes all mutable fields and returns a single-subscription [ByteStream]
  /// that emits the data being written to [sink].
  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_controller.stream);
  }
}

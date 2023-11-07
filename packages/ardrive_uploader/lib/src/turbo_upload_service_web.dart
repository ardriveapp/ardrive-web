import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive_uploader/src/turbo_upload_service_base.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:dio/dio.dart';
import 'package:fetch_client/fetch_client.dart';
import 'package:http/http.dart' as http;

class TurboUploadServiceImpl implements TurboUploadService {
  final Uri turboUploadUri;

  /// We are using Dio directly here. In the future we must adapt our ArDriveHTTP to support
  /// streaming uploads.
  // ArDriveHTTP httpClient;

  TurboUploadServiceImpl({
    required this.turboUploadUri,
  });

  final _fetchController = StreamController<List<int>>(sync: false);
  CancelToken _cancelToken = CancelToken();

  final client = FetchClient(
    mode: RequestMode.cors,
    streamRequests: true,
    cache: RequestCache.noCache,
  );

  @override
  Future<dynamic> postStream({
    required DataItemResult dataItem,
    required Wallet wallet,
    Function(double p1)? onSendProgress,
    required int size,
    required Map<String, dynamic> headers,
  }) {
    // max of 500mib
    if (dataItem.dataItemSize <= MiB(500).size) {
      return _uploadWithDio(
        dataItem: dataItem,
        wallet: wallet,
        onSendProgress: onSendProgress,
        size: size,
        headers: headers,
      );
    }

    return _uploadStreamWithFetchClient(
      dataItem: dataItem,
      wallet: wallet,
      onSendProgress: onSendProgress,
      size: size,
      headers: headers,
    );
  }

  Future<Response> _uploadWithDio({
    required DataItemResult dataItem,
    required Wallet wallet,
    Function(double p1)? onSendProgress,
    required int size,
    required Map<String, dynamic> headers,
  }) async {
    try {
      final url = '$turboUploadUri/v1/tx';

      final controller = StreamController<Uint8List>();

      controller
          .addStream(dataItem.streamGenerator())
          .then((value) => controller.close());

      final dio = Dio();

      final response = await dio.post(
        url,
        onSendProgress: (sent, total) {
          onSendProgress?.call(sent / total);
        },
        data: controller.stream, // Creates a Stream<List<int>>.
        options: Options(
          headers: {
            // stream
            Headers.contentTypeHeader: 'application/octet-stream',
            Headers.contentLengthHeader: size, // Set the content-length.
          }..addAll(headers),
        ),
        cancelToken: _cancelToken,
      );

      print('Response from turbo: ${response.statusCode}');

      return response;
    } catch (e) {
      print('Error on turbo upload: $e');
      if (_isCanceled) {
        _cancelToken = CancelToken();

        _cancelToken.cancel();
      }
      rethrow;
    }
  }

  Future<FetchResponse> _uploadStreamWithFetchClient({
    required DataItemResult dataItem,
    required Wallet wallet,
    Function(double)? onSendProgress,
    required int size,
    required Map<String, dynamic> headers,
  }) async {
    final url = '$turboUploadUri/v1/tx';

    int dataItemSize = 0;

    StreamTransformer<Uint8List, Uint8List> createPassthroughTransformer() {
      return StreamTransformer.fromHandlers(
        handleData: (Uint8List data, EventSink<Uint8List> sink) {
          sink.add(data);
        },
        handleError: (Object error, StackTrace stackTrace, EventSink sink) {
          sink.addError(error, stackTrace);
        },
        handleDone: (EventSink sink) {
          sink.close();
        },
      );
    }

    final request = ArDriveStreamedRequest(
      'POST',
      Uri.parse(url),
      _fetchController,
    )..headers.addAll({
        'content-type': 'application/octet-stream',
      });

    _fetchController
        .addStream(
      dataItem.streamGenerator().transform(
            createPassthroughTransformer(),
          ),
    )
        .then((value) {
      print('Done');
      request.sink.close();
    });

    _fetchController.onPause = () {
      print('Paused');
    };

    _fetchController.onResume = () {
      print('Resumed');
    };

    try {
      request.contentLength = dataItemSize;
      request.persistentConnection = false;

      print('is persistent connection?${request.persistentConnection}');

      final response = await client.send(request);

      print(await utf8.decodeStream(response.stream));

      return response;
    } catch (e) {
      print('Error on turbo upload using FetchClient: $e');
      rethrow;
    }
  }

  @override
  Future<void> cancel() async {
    _cancelToken.cancel();
    client.close();
    _fetchController.close();
    _isCanceled = true;
    print('Stream closed');
  }

  bool _isCanceled = false;
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

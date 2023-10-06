import 'dart:async';

import 'package:ardrive_uploader/src/turbo_upload_service_base.dart';
import 'package:arweave/arweave.dart';
import 'package:dio/dio.dart';

class TurboUploadServiceImpl implements TurboUploadService<Response> {
  final Uri turboUploadUri;

  /// We are using Dio directly here. In the future we must adapt our ArDriveHTTP to support
  /// streaming uploads.
  // ArDriveHTTP httpClient;

  TurboUploadServiceImpl({
    required this.turboUploadUri,
  });

  /// We are using Dio directly here. In the future we must adapt our ArDriveHTTP to support
  /// streaming uploads.
  /// This is a temporary solution.
  @override
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
      dataItemSize += data.length;
    }

    final dio = Dio();

    final response = await dio.post(
      url,
      onSendProgress: (sent, total) {
        print('Sent: $sent, total: $total');
        onSendProgress?.call(sent / total);
      },
      data: dataItem.streamGenerator(), // Creates a Stream<List<int>>.
      options: Options(
        headers: {
          // stream
          Headers.contentTypeHeader: 'application/octet-stream',
          Headers.contentLengthHeader: dataItemSize, // Set the content-length.
        }..addAll(headers),
      ),
    );

    print('Response from turbo: ${response.statusCode}');

    return response;
  }

  @override
  bool get isPossibleGetProgress => true;
}

class TurboUploadExceptions implements Exception {}

class TurboUploadTimeoutException implements TurboUploadExceptions {}

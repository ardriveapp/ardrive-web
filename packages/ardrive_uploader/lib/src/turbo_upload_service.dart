import 'package:arweave/arweave.dart';
import 'package:dio/dio.dart';

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

    final dio = Dio();

    int size = 0;

    await for (final data in dataItem.streamGenerator()) {
      size += data.length;
    }

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
}

class TurboUploadExceptions implements Exception {}

class TurboUploadTimeoutException implements TurboUploadExceptions {}

import 'package:ardrive_http/ardrive_http.dart';
import 'package:arweave/arweave.dart';
import 'package:dio/dio.dart';

class TurboService {
  final Uri turboUri;
  final int allowedDataItemSize;
  late ArDriveHTTP httpClient;

  TurboService({
    required this.turboUri,
    required this.allowedDataItemSize,
    required this.httpClient,
  });

  Future<void> postDataItem({required DataItem dataItem}) async {
    final dioInstance = httpClient.dio();
    final options = Options(contentType: 'application/octet-stream');
    await dioInstance.post(
      '${turboUri}v1/tx',
      options: options,
      data: Stream.fromIterable([(await dataItem.asBinary()).toBytes()]),
    );
  }
}

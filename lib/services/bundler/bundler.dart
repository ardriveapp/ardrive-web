import 'package:ardrive_http/ardrive_http.dart';
import 'package:arweave/arweave.dart';
import 'package:dio/dio.dart';

class BundlerService {
  final Uri bundlerUri;
  final int allowedDataItemSize;
  late ArDriveHTTP httpClient;

  BundlerService({
    required this.bundlerUri,
    required this.allowedDataItemSize,
    required this.httpClient,
  });

  Future<void> postDataItem({required DataItem dataItem}) async {
    final dioInstance = httpClient.dio();
    final options = Options(contentType: 'application/octet-stream');
    await dioInstance.post(
      '${bundlerUri}v1/tx',
      options: options,
      data: Stream.fromIterable([(await dataItem.asBinary()).toBytes()]),
    );
  }
}

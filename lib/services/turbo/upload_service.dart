import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:arweave/arweave.dart';

class UploadService {
  final bool useTurboUpload = true;
  final Uri turboUploadUri;
  final int allowedDataItemSize;
  ArDriveHTTP httpClient;

  UploadService({
    required this.turboUploadUri,
    required this.allowedDataItemSize,
    required this.httpClient,
  });

  Future<void> postDataItem({required DataItem dataItem}) async {
    final acceptedStatusCodes = [200, 202, 204];

    final response = await httpClient.postBytes(
      url: '$turboUploadUri/v1/tx',
      data: (await dataItem.asBinary()).toBytes(),
    );
    if (!acceptedStatusCodes.contains(response.statusCode)) {
      logger.e(response.data);
      throw Exception(
        'Turbo upload failed with status code ${response.statusCode}',
      );
    }
  }
}

class DontUseUploadService implements UploadService {
  @override
  int get allowedDataItemSize => throw UnimplementedError();

  @override
  Future<void> postDataItem({required DataItem dataItem}) {
    throw UnimplementedError();
  }

  @override
  Uri get turboUploadUri => throw UnimplementedError();

  @override
  bool get useTurboUpload => false;

  @override
  late ArDriveHTTP httpClient;
}

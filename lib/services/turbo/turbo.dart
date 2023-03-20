import 'package:ardrive_http/ardrive_http.dart';
import 'package:arweave/arweave.dart';

class TurboService {
  final bool useTurbo = true;
  final Uri turboUri;
  final int allowedDataItemSize;
  ArDriveHTTP httpClient;

  TurboService({
    required this.turboUri,
    required this.allowedDataItemSize,
    required this.httpClient,
  });

  Future<void> postDataItem({required DataItem dataItem}) async {
    final acceptedStatusCodes = [200, 202, 204];
    final response = await httpClient.postBytes(
      url: '$turboUri/v1/tx',
      data: (await dataItem.asBinary()).toBytes(),
    );
    if (!acceptedStatusCodes.contains(response.statusCode)) {
      throw Exception(
        'Turbo upload failed with status code ${response.statusCode}',
      );
    }
  }
}

class DontUseTurbo implements TurboService {
  @override
  int get allowedDataItemSize => throw UnimplementedError();

  @override
  Future<void> postDataItem({required DataItem dataItem}) {
    throw UnimplementedError();
  }

  @override
  Uri get turboUri => throw UnimplementedError();

  @override
  bool get useTurbo => false;

  @override
  late ArDriveHTTP httpClient;
}

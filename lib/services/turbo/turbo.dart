import 'package:ardrive_http/ardrive_http.dart';
import 'package:arweave/arweave.dart';

class TurboService {
  final bool useTurbo;
  final Uri turboUri;
  final int allowedDataItemSize;
  ArDriveHTTP httpClient;

  TurboService({
    required this.useTurbo,
    required this.turboUri,
    required this.allowedDataItemSize,
    required this.httpClient,
  });

  Future<void> postDataItem({required DataItem dataItem}) async {
    await httpClient.postBytes(
      url: '${turboUri}v1/tx',
      dataBytes: (await dataItem.asBinary()).toBytes(),
    );
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

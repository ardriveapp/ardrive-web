import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive/utils/turbo_utils.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:arweave/arweave.dart';
import 'package:uuid/uuid.dart';

class TurboUploadService {
  final bool useTurboUpload = true;
  final Uri turboUploadUri;
  final int allowedDataItemSize;
  ArDriveHTTP httpClient;

  TurboUploadService({
    required this.turboUploadUri,
    required this.allowedDataItemSize,
    required this.httpClient,
  });

  Future<void> postDataItem({
    required DataItem dataItem,
    required Wallet wallet,
  }) async {
    final acceptedStatusCodes = [200, 202, 204];

    final nonce = const Uuid().v4();
    final publicKey = await wallet.getPublicKey();
    final signature = await signNonceAndData(
      nonce: nonce,
      wallet: wallet,
    );

    final response = await httpClient.postBytes(
      url: '$turboUploadUri/v1/tx',
      headers: {
        'x-nonce': nonce,
        'x-signature': signature,
        'x-public-key': publicKeyToHeader(publicKey),
      },
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

class DontUseUploadService implements TurboUploadService {
  @override
  int get allowedDataItemSize => throw UnimplementedError();

  @override
  Future<void> postDataItem({
    required DataItem dataItem,
    required Wallet wallet,
  }) {
    throw UnimplementedError();
  }

  @override
  Uri get turboUploadUri => throw UnimplementedError();

  @override
  bool get useTurboUpload => false;

  @override
  late ArDriveHTTP httpClient;
}

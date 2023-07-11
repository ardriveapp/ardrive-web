import 'dart:async';

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

  Stream<double> postDataItemWithProgress({
    required DataItem dataItem,
    required Wallet wallet,
  }) {
    final controller = StreamController<double>();

    controller.add(0);

    try {
      postDataItem(
        dataItem: dataItem,
        wallet: wallet,
        onSendProgress: (value) {
          controller.add(value);
          if (value == 1) {
            controller.close();
          }
        },
      );
    } catch (e) {
      logger.e(e);
      controller.addError(e);
      controller.close();
    }

    return controller.stream;
  }

  Future<void> postDataItem({
    required DataItem dataItem,
    required Wallet wallet,
    Function(double)? onSendProgress,
  }) async {
    final acceptedStatusCodes = [200, 202, 204];

    final nonce = const Uuid().v4();
    final publicKey = await wallet.getOwner();
    final signature = await signNonceAndData(
      nonce: nonce,
      wallet: wallet,
    );

    final data = (await dataItem.asBinary()).toBytes();

    final response = await httpClient.postBytes(
      url: '$turboUploadUri/v1/tx',
      headers: {
        'x-nonce': nonce,
        'x-signature': signature,
        'x-public-key': publicKey,
      },
      data: data,
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
    Function(double)? onSendProgress,
  }) {
    throw UnimplementedError();
  }

  @override
  Uri get turboUploadUri => throw UnimplementedError();

  @override
  bool get useTurboUpload => false;

  @override
  late ArDriveHTTP httpClient;

  @override
  Stream<double> postDataItemWithProgress(
      {required DataItem dataItem, required Wallet wallet}) {
    // TODO: implement postDataItemWithProgress
    throw UnimplementedError();
  }
}

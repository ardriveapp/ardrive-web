import 'dart:async';

import 'package:ardrive/core/arconnect/safe_arconnect_action.dart';
import 'package:ardrive/utils/app_platform.dart';
import 'package:ardrive/utils/data_item_utils.dart';
import 'package:ardrive/utils/html/html_util.dart';
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
  final TabVisibilitySingleton _tabVisibility;

  TurboUploadService({
    required this.turboUploadUri,
    required this.allowedDataItemSize,
    required this.httpClient,
    required TabVisibilitySingleton tabVisibilitySingleton,
  }) : _tabVisibility = tabVisibilitySingleton;

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
      ).then((value) {
        controller.add(1.0);
        controller.close();
      });
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
    final publicKey = await safeArConnectAction<String>(
      _tabVisibility,
      (_) async {
        logger.d('Getting public key with safe ArConnect action');
        return wallet.getOwner();
      },
    );
    final signature = await safeArConnectAction<String>(
      _tabVisibility,
      (_) async {
        logger.d('Signing with safe ArConnect action');
        return signNonceAndData(
          nonce: nonce,
          wallet: wallet,
        );
      },
    );

    final headers = {
      'x-nonce': nonce,
      'x-signature': signature,
      'x-public-key': publicKey,
    };

    final url = '$turboUploadUri/v1/tx';
    const receiveTimeout = Duration(days: 365);
    const sendTimeout = Duration(days: 365);

    if (AppPlatform.isMobile) {
      final response = await httpClient.postBytes(
        url: url,
        onSendProgress: onSendProgress,
        data: (await dataItem.asBinary()).toBytes(),
        headers: headers,
        receiveTimeout: receiveTimeout,
        sendTimeout: sendTimeout,
      );

      if (!acceptedStatusCodes.contains(response.statusCode)) {
        logger.e(response.data);
        throw Exception(
          'Turbo upload failed with status code ${response.statusCode}',
        );
      }
      return;
    }

    final response = await httpClient.postBytesAsStream(
        url: url,
        onSendProgress: onSendProgress,
        headers: headers,
        receiveTimeout: receiveTimeout,
        sendTimeout: sendTimeout,
        data: await convertDataItemToStreamBytes(dataItem));

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

  @override
  TabVisibilitySingleton get _tabVisibility => throw UnimplementedError();
}

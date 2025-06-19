import 'dart:async';

import 'package:ardrive/utils/data_item_utils.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';

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
      ).then((value) {
        logger.i('Closing upload stream on UploadService for Turbo');
        controller.close();
      }).onError((error, stackTrace) {
        logger.e(
            'Catching error in postDataItemWithProgress', error, stackTrace);
        controller.addError(error ?? Exception('Error'));
        logger.e('Closing stream');
        controller.close();
      });
    } catch (e) {
      logger.e('Catching an uncaught error on UploadService', e);
      controller.addError(e);
      logger.e('Closing stream');
      controller.close();
    }

    return controller.stream;
  }

  Future<void> postDataItem({
    required DataItem dataItem,
    required Wallet wallet,
    Function(double)? onSendProgress,
    Map<String, String>? headers,
  }) async {
    headers ??= {};
    try {
      final acceptedStatusCodes = [200, 202, 204];

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
          logger.e('Error posting bytes', response.data);
          throw _handleException(response);
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
        logger.e('Error posting bytes', response.data);
        throw _handleException(response);
      }
    } catch (e, stacktrace) {
      logger.e('Catching error in postDataItem', e, stacktrace);
      throw _handleException(e);
    }
  }

  Exception _handleException(Object error) {
    logger.e('Handling exception in UploadService', error);

    if (error is ArDriveHTTPResponse && error.statusCode == 408) {
      logger.e(
        'Handling exception in UploadService with status code: ${error.statusCode}',
        error,
      );

      return TurboUploadTimeoutException();
    }
    if (error is ArDriveHTTPException && error.statusCode == 408) {
      logger.e(
        'Handling exception in UploadService with status code: ${error.statusCode}',
        error,
      );

      return TurboUploadTimeoutException();
    }

    return Exception(error);
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
    Map<String, String>? headers,
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

  @override
  Exception _handleException(Object error) {
    // TODO: implement _handleException
    throw UnimplementedError();
  }
}

class TurboUploadExceptions implements Exception {}

class TurboUploadTimeoutException implements TurboUploadExceptions {}

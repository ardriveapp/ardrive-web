import 'dart:async';
import 'dart:convert';

import 'package:ardrive/utils/data_item_utils.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
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
  }) {
    unawaited(refreshMaxItemBytes());
  }

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

    final statusCode = error is ArDriveHTTPResponse
        ? error.statusCode
        : error is ArDriveHTTPException
            ? error.statusCode
            : null;

    final typed = turboExceptionForStatusCode(statusCode);
    if (typed != null) {
      logger.e(
        'Handling exception in UploadService with status code: $statusCode',
        error,
      );
      return typed;
    }

    return Exception(error);
  }

  /// Server-reported maximum size of an item eligible for free upload,
  /// fetched once from `GET /v1/info`. Falls back to the config-injected
  /// [allowedDataItemSize] until (or unless) the server reports one.
  int? _serverMaxItemBytes;

  int get maxFreeItemSizeBytes => _serverMaxItemBytes ?? allowedDataItemSize;

  Future<void> refreshMaxItemBytes() async {
    try {
      final response = await httpClient.get(url: '$turboUploadUri/v1/info');
      final raw = response.data;
      final data = raw is String ? json.decode(raw) : raw;
      final value = data is Map ? data['maxItemBytes'] : null;
      if (value is int && value > 0) {
        _serverMaxItemBytes = value;
        logger.d('Turbo free item size limit from /v1/info: $value bytes');
      }
    } catch (e) {
      logger.w(
          'Could not fetch turbo /v1/info; using configured item size: $e');
    }
  }
}

/// True when [error] indicates the upload service rejected an operation for
/// payment reasons (free allowance exhausted / insufficient credits). Used by
/// metadata-op blocs to choose payment-specific failure UX.
bool isTurboPaymentError(Object? error) {
  // The app-side TurboUploadService throws TurboPaymentRequiredException on
  // 402; the ardrive_uploader package throws UnderFundException (sometimes
  // wrapped in an UploadStrategyException). Recognize all of them so every
  // upload path — metadata ops AND file/folder/manifest uploads — maps a
  // payment rejection to the same UX.
  if (error is TurboPaymentRequiredException) return true;
  if (error is UnderFundException) return true;
  if (error is UploadStrategyException && error.error is UnderFundException) {
    return true;
  }
  return false;
}

/// Like [isTurboPaymentError] but inspects a collection of failed upload
/// tasks (the ardrive_uploader package reports failures as a task list).
bool anyTaskIsTurboPaymentError(Iterable<Object?> taskErrors) {
  return taskErrors.any(isTurboPaymentError);
}

/// Maps a turbo upload HTTP status code to a typed exception, or null for
/// codes without special semantics.
Exception? turboExceptionForStatusCode(int? statusCode) {
  switch (statusCode) {
    case 408:
      return TurboUploadTimeoutException();
    case 402:
      return TurboPaymentRequiredException();
    case 429:
      return TurboRateLimitException();
    default:
      return null;
  }
}

class DontUseUploadService implements TurboUploadService {
  @override
  int get allowedDataItemSize => throw UnimplementedError();

  // Same-library interface implementation includes private members.
  @override
  int? _serverMaxItemBytes;

  @override
  int get maxFreeItemSizeBytes => throw UnimplementedError();

  @override
  Future<void> refreshMaxItemBytes() async {}

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
  Exception _handleException(Object error) {
    // TODO: implement _handleException
    throw UnimplementedError();
  }
}

class TurboUploadExceptions implements Exception {}

class TurboUploadTimeoutException implements TurboUploadExceptions {}

/// The upload was rejected for payment reasons (HTTP 402): the free
/// allowance is exhausted and/or credits are insufficient. Must never be
/// blindly retried.
class TurboPaymentRequiredException implements TurboUploadExceptions {}

/// The upload was rate-limited (HTTP 429). Must never be blindly retried.
class TurboRateLimitException implements TurboUploadExceptions {}

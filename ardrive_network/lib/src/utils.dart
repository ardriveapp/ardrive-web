import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';

RetryInterceptor getDioRetrySettings({
  required Dio dio,
  required int retries,
  required int retryDelayMs,
  required int retryAttempts,
  required bool noLogs,
}) {
  Duration retryDelay(int retryCount) =>
      Duration(milliseconds: retryDelayMs) * pow(1.5, retryCount);

  List<Duration> retryDelays =
      List.generate(retries, (index) => retryDelay(index));

  FutureOr<bool> setRetryAttempt(DioError error, int attempt) async {
    bool shouldRetry =
        await RetryInterceptor.defaultRetryEvaluator(error, attempt);

    if (shouldRetry) {
      retryAttempts = attempt;
    }

    return shouldRetry;
  }

  return RetryInterceptor(
    dio: dio,
    logPrint: noLogs ? null : print,
    retries: retries,
    retryDelays: retryDelays,
    retryEvaluator: setRetryAttempt,
  );
}

import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:ardrive_network/src/responses.dart';
import 'package:ardrive_network/src/utils.dart';
import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter/foundation.dart';
import 'package:isolated_worker/js_isolated_worker.dart';

class ArdriveNetwork {
  late int retries;
  late int retryDelayMs;
  late bool noLogs;
  bool _areScriptsImported = false;
  int retryAttempts = 0;

  ArdriveNetwork({
    int retries = 8,
    int retryDelayMs = 200,
    noLogs = false,
  }) {
    this.retries = retries;
    this.retryDelayMs = retryDelayMs;
    this.noLogs = noLogs;
  }

  Dio dio() {
    final dio = Dio();

    if (!noLogs) {
      dio.interceptors.add(LogInterceptor());
    }

    if (retries > 0) {
      dio.interceptors.add(_getDioRetrySettings(dio));
    }

    return dio;
  }

  Future<ArDriveNetworkResponse> get({
    required String url,
    bool isJson = false,
    bool asBytes = false,
  }) async {
    checkIsJsonAndAsBytesParams(isJson, asBytes);

    if (kIsWeb) {
      if (await _loadWebWorkers()) {
        return await _getWeb(
          url: url,
          isJson: isJson,
          asBytes: asBytes,
        );
      }
    }

    final Map getIOParams = Map();
    getIOParams['url'] = url;
    getIOParams['asBytes'] = asBytes;

    return await compute(_getIO, getIOParams);
  }

  Future<ArDriveNetworkResponse> getJson(String url) async {
    return get(url: url, isJson: true);
  }

  Future<ArDriveNetworkResponse> getAsBytes(String url) async {
    return get(url: url, asBytes: true);
  }

  Future<ArDriveNetworkResponse> _getIO(Map params) async {
    final String url = params['url'];
    final bool asBytes = params['asBytes'];

    try {
      var response;
      if (asBytes) {
        response = await this.dio().get<List<int>>(
              url,
              options: Options(responseType: ResponseType.bytes),
            );
      } else {
        response = await this.dio().get(url);
      }

      return ArDriveNetworkResponse(
          data: response.data,
          statusCode: response.statusCode,
          statusMessage: response.statusMessage,
          retryAttempts: this.retryAttempts);
    } catch (error) {
      throw ArDriveNetworkException(
          retryAttempts: this.retryAttempts, dioException: error);
    }
  }

  Future<ArDriveNetworkResponse> _getWeb({
    required String url,
    required bool isJson,
    required bool asBytes,
  }) async {
    try {
      final LinkedHashMap<dynamic, dynamic> response =
          await JsIsolatedWorker().run(
        functionName: 'get',
        arguments: [
          url,
          isJson,
          asBytes,
          retries,
          retryDelayMs,
          noLogs,
        ],
      );

      if (response['error'] != null) {
        this.retryAttempts = response['retryAttempts'];

        throw response['error'];
      }

      return ArDriveNetworkResponse(
        data: asBytes ? Uint8List.view(response['data']) : response['data'],
        statusCode: response['statusCode'],
        statusMessage: response['statusMessage'],
        retryAttempts: response['retryAttempts'],
      );
    } catch (error) {
      throw ArDriveNetworkException(
          retryAttempts: this.retryAttempts, dioException: error);
    }
  }

  Future<bool> _loadWebWorkers() async {
    const List<String> _jsScript = <String>['ardrive-network.js'];
    bool jsLoaded = false;

    if (!_areScriptsImported) {
      jsLoaded = await JsIsolatedWorker().importScripts(_jsScript);
      _areScriptsImported = !jsLoaded;
    }

    if (jsLoaded) {
      return true;
    } else {
      throw Exception('ArDriveNetwork Web worker is not available!');
    }
  }

  RetryInterceptor _getDioRetrySettings(Dio dio) {
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
}

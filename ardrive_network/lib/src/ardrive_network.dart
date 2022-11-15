import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:ardrive_network/src/responses.dart';
import 'package:ardrive_network/src/utils.dart';
import 'package:dio/dio.dart';
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
      final dioRetry = getDioRetrySettings(
        dio: dio,
        retries: retries,
        retryDelayMs: retryDelayMs,
        retryAttempts: retryAttempts,
        noLogs: noLogs,
      );

      dio.interceptors.add(dioRetry);
    }

    return dio;
  }

  Future<ArDriveNetworkResponse> getJson(String url) async {
    if (kIsWeb) {
      if (await _loadWebWorkers()) {
        return await _getJsonWeb(url);
      }
    }

    return await compute(_getJsonIO, url);
  }

  Future<ArDriveNetworkResponse> _getJsonIO(String url) async {
    try {
      Response<String> response = await this.dio().get(url);

      return ArDriveNetworkResponse(
          data: jsonDecode(response.data ?? ''),
          statusCode: response.statusCode,
          statusMessage: response.statusMessage,
          retryAttempts: this.retryAttempts);
    } catch (error) {
      throw ArDriveNetworkException(
          retryAttempts: this.retryAttempts, dioException: error);
    }
  }

  Future<ArDriveNetworkResponse> _getJsonWeb(String url) async {
    try {
      final LinkedHashMap<dynamic, dynamic> response =
          await JsIsolatedWorker().run(
        functionName: 'getJson',
        arguments: [
          url,
          this.retries,
          this.retryDelayMs,
          this.noLogs,
        ],
      );

      if (response['error'] != null) {
        this.retryAttempts = response['retryAttempts'];

        throw response['error'];
      }

      return ArDriveNetworkResponse(
        data: response['data'],
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
}

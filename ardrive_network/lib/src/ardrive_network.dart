import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';
import 'package:isolated_worker/js_isolated_worker.dart';

const List<String> _jsScript = <String>['ardrive-network.js'];

class ArdriveNetwork {
  bool _areScriptsImported = false;
  late int retries;
  late int retryDelayMs;

  ArdriveNetwork({int retries = 8, int retryDelayMs = 200}) {
    this.retries = retries;
    this.retryDelayMs = retryDelayMs;
  }

  Future<LinkedHashMap<dynamic, dynamic>> getJson(String url) async {
    if (kIsWeb) {
      if (!_areScriptsImported) {
        await JsIsolatedWorker().importScripts(_jsScript);
        _areScriptsImported = true;
      }

      return await JsIsolatedWorker().run(
        functionName: 'getJson',
        arguments: url,
      ) as LinkedHashMap<dynamic, dynamic>;
    }

    final computedData = await compute(_getJsonCompute, url);
    return computedData;
  }

  bool _defaultWhenError(Object error, StackTrace stackTrace) => true;

  Future<LinkedHashMap<dynamic, dynamic>> _getJsonCompute(String url) async {
    final client = RetryClient(http.Client(),
        retries: retries, delay: _retryDelay, whenError: _defaultWhenError);
    final uri = Uri.parse(url);
    http.Response response;

    try {
      response = await client.get(uri);
      final dynamic jsonResponse = jsonDecode(response.body);
      final result = LinkedHashMap<String, dynamic>();

      result['statusCode'] = response.statusCode;
      result['reasonPhrase'] = response.reasonPhrase;
      result['jsonResponse'] = jsonResponse;
      return result;
    } catch (error) {
      final err = LinkedHashMap<String, dynamic>();
      err['err'] = error;
      return err;
    } finally {
      client.close();
    }
  }

  Duration _retryDelay(int retryCount) =>
      Duration(milliseconds: retryDelayMs) * pow(1.5, retryCount);
}

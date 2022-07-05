import 'dart:async';

import 'package:ardrive/utils/response_handler.dart';
import 'package:http/http.dart';
import 'package:retry/retry.dart';

class HttpRetryOptions {
  HttpRetryOptions({this.retryIf, this.onRetry});

  final FutureOr<bool> Function(Exception)? retryIf;
  final FutureOr<void> Function(Exception)? onRetry;
}

class HttpRetry {
  HttpRetry(this.responseHandler, this.httpRetryOptions);

  final ResponseHandler responseHandler;
  final HttpRetryOptions httpRetryOptions;

  Future<Response> processRequest(Future<Response> Function() request) {
    int retryTimes = 0;
    return retry(
        () async {
          final response = await request();

          /// Handle errors if have
          responseHandler.handle(response);

          if (retryTimes > 0) {
            print('Succesfully get the response after $retryTimes');
          }

          return response;
        },
        randomizationFactor: 0,
        onRetry: (e) {
          ++retryTimes;
          httpRetryOptions.onRetry?.call(e);
        },
        retryIf: httpRetryOptions.retryIf);
  }
}

import 'dart:async';

import 'package:ardrive/utils/response_handler.dart';
import 'package:http/http.dart';
import 'package:retry/retry.dart';

class HttpRetryOptions {
  HttpRetryOptions({this.retryIf, this.onRetry, this.maxAttempts = 8});

  final FutureOr<bool> Function(Exception)? retryIf;
  final FutureOr<void> Function(Exception)? onRetry;
  final int maxAttempts;
}

class HttpRetry {
  HttpRetry(this.responseHandler, this.httpRetryOptions);

  final ResponseHandler responseHandler;
  final HttpRetryOptions httpRetryOptions;

  Future<Response> processRequest(Future<Response> Function() request) {
    int retryAttempts = 0;
    return retry(
        () async {
          final response = await request();

          /// Handle errors if have
          responseHandler.handle(response);

          if (retryAttempts > 0) {
            print(
                'Succesfully get the response after $retryAttempts attempt(s)');
          }

          return response;
        },
        maxAttempts: httpRetryOptions.maxAttempts,
        randomizationFactor: 0,
        onRetry: (e) {
          ++retryAttempts;
          httpRetryOptions.onRetry?.call(e);
        },
        retryIf: httpRetryOptions.retryIf);
  }
}

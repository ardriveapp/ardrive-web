import 'dart:async';

import 'package:ardrive/utils/response_handler.dart';
import 'package:http/http.dart';
import 'package:retry/retry.dart';

class HttpRetry {
  HttpRetry(this.responseHandler);

  final ResponseHandler responseHandler;

  Future<Response> processRequest(Future<Response> Function() request,
      {FutureOr<bool> Function(Exception)? retryIf,
      FutureOr<void> Function(Exception)? onRetry}) {
    return retry(() async {
      final response = await request();

      /// Handle errors if have
      responseHandler.handle(response);

      return response;
    }, onRetry: onRetry, retryIf: retryIf);
  }
}

import 'package:http/http.dart';
import 'package:retry/retry.dart';

import 'error.dart';
import 'response_handler.dart';

class HttpRetry {
  HttpRetry(this.responseHandler);

  final GatewayResponseHandler responseHandler;

  Future<Response> processRequest(Future<Response> Function() request) {
    return retry(() async {
      final response = await request();

      return responseHandler.handle(response);
    }, onRetry: (exception) {
      if (exception is NetworkError) {
        print(
          'Retrying for ${exception.runtimeType} exception\n'
          'for route ${exception.requestRoute}\n'
          'and status code ${exception.statusCode}',
        );
        return;
      }

      print('Retrying for unknown exception: ${exception.toString()}');
    }, retryIf: (exception) {
      return exception is! RateLimitError;
    });
  }
}

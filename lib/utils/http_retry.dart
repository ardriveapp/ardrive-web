import 'package:http/http.dart';
import 'package:retry/retry.dart';

import 'error.dart';
import 'network_error_handler.dart';

class HttpRetry {
  HttpRetry(this.errorHandler);

  final NetworkErrorHandler errorHandler;

  Future<Response> call(Future<Response> Function() request) {
    return retry(() async {
      final response = await request();

      if (response.statusCode == 200) {
        return response;
      }

      throw errorHandler.handle(response);
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

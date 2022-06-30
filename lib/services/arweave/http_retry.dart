import 'package:ardrive/services/arweave/error/error.dart';
import 'package:ardrive/services/arweave/error/response_handler.dart';
import 'package:http/http.dart';
import 'package:retry/retry.dart';

class HttpRetry {
  HttpRetry(this.responseHandler);

  final ResponseHandler responseHandler;

  Future<Response> processRequest(Future<Response> Function() request) {
    return retry(() async {
      final response = await request();

      /// Handle errors if have
      responseHandler.handle(response);

      return response;
    }, onRetry: (exception) {
      if (exception is GatewayError) {
        print(
          'Retrying for ${exception.runtimeType} exception\n'
          'for route ${exception.requestUrl}\n'
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

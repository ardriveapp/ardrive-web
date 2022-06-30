import 'package:ardrive/services/arweave/error/gateway_error.dart';
import 'package:ardrive/utils/response_handler.dart';
import 'package:http/http.dart';

/// Throws a `GatewayError` exception for `statusCode` different from 200
///
class GatewayResponseHandler implements ResponseHandler {
  @override
  void handle(Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      throw GatewayError.fromResponse(response);
    }
  }
}

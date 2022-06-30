import 'package:ardrive/services/arweave/error/error.dart';
import 'package:http/http.dart';

/// `handle` verifies if the response has any erros, and if so, should throw
/// an exception.
abstract class ResponseHandler {
  void handle(Response response);
}

/// Throws a `GatewayNetworkError` exception for `statusCode` different from 200
/// 
class GatewayResponseHandler implements ResponseHandler {
  @override
  void handle(Response response) {
    if (response.statusCode != 200) {
      throw GatewayNetworkError.fromResponse(response);
    }
  }
}

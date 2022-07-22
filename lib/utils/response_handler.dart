import 'package:ardrive/services/arweave/error/gateway_error.dart';
import 'package:http/http.dart';

/// `handle` verifies if the response has any erros, and if so, should throw
/// an exception.
abstract class ResponseHandler {
  void handle(Response response);
}


abstract class ARIOException implements Exception {
  final String message;

  ARIOException(this.message);

  @override
  String toString() {
    return message;
  }
}

class GetIOTokensException extends ARIOException {
  GetIOTokensException(super.message);
}

class GetGatewaysException extends ARIOException {
  GetGatewaysException(super.message);
}

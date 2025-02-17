import 'package:equatable/equatable.dart';
import 'package:http/http.dart';

// ignore: constant_identifier_names
const int RATE_LIMIT_ERROR = 429;
// ignore: constant_identifier_names
const int UNEXPECTED_REDIRECTION = 302;

/// Handles `http` exceptions in the gateway context
abstract class GatewayError extends Equatable implements Exception {
  const GatewayError(
      {this.requestUrl, required this.statusCode, required this.reasonPhrase});

  final int statusCode;
  final String? requestUrl;
  final String reasonPhrase;

  factory GatewayError.fromResponse(Response response) {
    final requestUrl = response.request?.url.path;
    final statusCode = response.statusCode;
    final reasonPhrase = response.reasonPhrase ?? '';
    if (statusCode >= 500) {
      return ServerError(
          statusCode: statusCode,
          requestUrl: requestUrl,
          reasonPhrase: reasonPhrase);
    }
    if (statusCode == 429) {
      return RateLimitError(requestUrl: requestUrl, reasonPhrase: reasonPhrase);
    }
    if (statusCode == 302) {
      return UnexpectedRedirection(
          reasonPhrase: reasonPhrase, requestUrl: requestUrl);
    }
    return UnknownNetworkError(
        statusCode: statusCode,
        requestUrl: requestUrl,
        reasonPhrase: reasonPhrase);
  }
}

class UnexpectedRedirection extends GatewayError {
  const UnexpectedRedirection({required super.reasonPhrase, super.requestUrl})
      : super(statusCode: UNEXPECTED_REDIRECTION);

  @override
  List<Object?> get props => [statusCode, reasonPhrase, requestUrl];
}

/// 5xx Errors
class ServerError extends GatewayError {
  const ServerError(
      {required super.statusCode,
      required super.reasonPhrase,
      super.requestUrl})
      : assert(statusCode >= 500);
  @override
  List<Object?> get props => [statusCode, reasonPhrase, requestUrl];
}

/// 429s Errors
class RateLimitError extends GatewayError {
  const RateLimitError({required super.reasonPhrase, super.requestUrl})
      : super(statusCode: RATE_LIMIT_ERROR);

  @override
  List<Object?> get props => [statusCode, reasonPhrase, requestUrl];
}

class UnknownNetworkError extends GatewayError {
  const UnknownNetworkError(
      {required super.statusCode,
      required super.reasonPhrase,
      super.requestUrl});

  @override
  List<Object?> get props => [statusCode, reasonPhrase, requestUrl];
}

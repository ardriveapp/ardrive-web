import 'package:equatable/equatable.dart';
import 'package:http/http.dart';

// ignore: constant_identifier_names
const int RATE_LIMIT_ERROR = 429;

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
    if (response.statusCode >= 500) {
      return ServerError(
          statusCode: statusCode,
          requestUrl: requestUrl,
          reasonPhrase: reasonPhrase);
    }
    if (response.statusCode == 429) {
      return RateLimitError(requestUrl: requestUrl, reasonPhrase: reasonPhrase);
    }
    return UnknownNetworkError(
        statusCode: statusCode,
        requestUrl: requestUrl,
        reasonPhrase: reasonPhrase);
  }
}

/// 5xx Errors
class ServerError extends GatewayError {
  const ServerError(
      {required int statusCode,
      required String reasonPhrase,
      String? requestUrl})
      : assert(statusCode >= 500),
        super(
            reasonPhrase: reasonPhrase,
            statusCode: statusCode,
            requestUrl: requestUrl);
  @override
  List<Object?> get props => [statusCode, reasonPhrase, requestUrl];
}

/// 429s Errors
class RateLimitError extends GatewayError {
  const RateLimitError({required String reasonPhrase, String? requestUrl})
      : super(
            reasonPhrase: reasonPhrase,
            statusCode: RATE_LIMIT_ERROR,
            requestUrl: requestUrl);

  @override
  List<Object?> get props => [statusCode, reasonPhrase, requestUrl];
}

class UnknownNetworkError extends GatewayError {
  const UnknownNetworkError(
      {required int statusCode,
      required String reasonPhrase,
      String? requestUrl})
      : super(
            reasonPhrase: reasonPhrase,
            statusCode: statusCode,
            requestUrl: requestUrl);

  @override
  List<Object?> get props => [statusCode, reasonPhrase, requestUrl];
}

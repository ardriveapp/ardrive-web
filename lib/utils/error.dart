// TODO(@thiagocarvalhodev): Add more error constants
import 'package:equatable/equatable.dart';

// ignore: constant_identifier_names
const int RATE_LIMIT_ERROR = 429;

abstract class ArDriveError implements Exception {}

/// Handles every `http` exception
abstract class NetworkError extends ArDriveError with EquatableMixin {
  NetworkError(
      {this.requestRoute,
      required this.statusCode,
      required this.reasonPhrase});

  int statusCode;
  String? requestRoute;
  String reasonPhrase;
}

/// 5xx Errors
class ServerError extends NetworkError {
  ServerError(
      {required int statusCode,
      required String reasonPhrase,
      String? requestRoute})
      : super(
            reasonPhrase: reasonPhrase,
            statusCode: statusCode,
            requestRoute: requestRoute);

  @override
  List<Object?> get props => [statusCode, reasonPhrase, requestRoute];
}

class NetworkTimeOut extends NetworkError {
  NetworkTimeOut(
      {required int statusCode,
      required String reasonPhrase,
      String? requestRoute})
      : super(
            reasonPhrase: reasonPhrase,
            statusCode: statusCode,
            requestRoute: requestRoute);

  @override
  List<Object?> get props => [statusCode, reasonPhrase, requestRoute];
}

/// 429s Errors
class RateLimitError extends NetworkError {
  RateLimitError({required String reasonPhrase, String? requestRoute})
      : super(
            reasonPhrase: reasonPhrase,
            statusCode: RATE_LIMIT_ERROR,
            requestRoute: requestRoute);

  @override
  List<Object?> get props => [statusCode, reasonPhrase, requestRoute];
}

class UnknownNetworkError extends NetworkError {
  UnknownNetworkError(
      {required int statusCode,
      required String reasonPhrase,
      String? requestRoute})
      : super(
            reasonPhrase: reasonPhrase,
            statusCode: statusCode,
            requestRoute: requestRoute);

  @override
  List<Object?> get props => [statusCode, reasonPhrase, requestRoute];
}

class ConnectionError extends ArDriveError {}

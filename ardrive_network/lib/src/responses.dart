import 'package:equatable/equatable.dart';

class ArDriveNetworkResponse {
  ArDriveNetworkResponse({
    required this.data,
    this.statusCode,
    this.statusMessage,
    required this.retryAttempts,
  }) {
    this.data = data;
    this.statusCode = statusCode;
    this.statusMessage = statusMessage;
    this.retryAttempts = retryAttempts;
  }

  dynamic data;
  int? statusCode;
  String? statusMessage;
  int retryAttempts;
}

class ArDriveNetworkException extends Equatable implements Exception {
  final int retryAttempts;
  final Object dioException;

  ArDriveNetworkException(
      {required this.retryAttempts, required this.dioException});
  @override
  List<Object?> get props => [this.retryAttempts];

  @override
  String toString() {
    return '$dioException\nRetry attempts: $retryAttempts\n';
  }
}

abstract class ArDriveUploaderExceptions implements Exception {
  abstract final String message;
  abstract final Object? error;
}

abstract class UploadPreparationException
    implements ArDriveUploaderExceptions {}

class UploadCanceledException implements ArDriveUploaderExceptions {
  UploadCanceledException(this.message);

  @override
  final String message;
  @override
  Object? error;
}

abstract class UploadStrategyException implements UploadPreparationException {}

class MetadataTransactionUploadException extends UploadStrategyException {
  MetadataTransactionUploadException({
    required this.message,
    this.error,
  });

  @override
  final String message;
  @override
  Object? error;

  @override
  String toString() {
    return 'MetadataTransactionUploadException: $message. Error: ${error.toString()}';
  }
}

class DataTransactionUploadException implements UploadStrategyException {
  DataTransactionUploadException({
    required this.message,
    this.error,
  });

  @override
  final String message;
  @override
  Object? error;

  @override
  String toString() {
    return 'DataTransactionUploadException: $message. Error: ${error.toString()}';
  }
}

class BundleUploadException implements UploadStrategyException {
  BundleUploadException({
    required this.message,
    this.error,
  });

  @override
  final String message;
  @override
  Object? error;

  @override
  String toString() {
    return 'BundleUploadException: $message. Error: ${error.toString()}';
  }
}

abstract class NetworkException implements ArDriveUploaderExceptions {
  abstract final int? statusCode;
}

class FetchClientException implements NetworkException {
  FetchClientException({
    this.statusCode,
    required this.message,
    this.error,
  });

  @override
  final int? statusCode;
  @override
  final String message;
  @override
  Object? error;
}

class DioClientException implements NetworkException {
  DioClientException({
    this.statusCode,
    required this.message,
    this.error,
  });

  @override
  final int? statusCode;
  @override
  final String message;
  @override
  Object? error;
}

class UnknownNetworkException implements NetworkException {
  UnknownNetworkException({
    this.statusCode,
    required this.message,
    this.error,
  });

  @override
  final int? statusCode;
  @override
  final String message;
  @override
  Object? error;
}

class UnderFundException implements ArDriveUploaderExceptions {
  UnderFundException({
    required this.message,
    this.error,
  });

  @override
  final String message;
  @override
  Object? error;
}

class ThumbnailUploadException implements UploadStrategyException {
  ThumbnailUploadException({
    required this.message,
    this.error,
  });

  @override
  final String message;
  @override
  Object? error;
}

class TurboUploadTimeoutException implements ArDriveUploaderExceptions {
  TurboUploadTimeoutException({
    this.message = 'Turbo upload timeout',
    this.error,
  });

  @override
  final String message;
  @override
  Object? error;
}

/// The upload was rate-limited (HTTP 429). Must never be blindly retried.
class TurboRateLimitException implements ArDriveUploaderExceptions {
  TurboRateLimitException({
    this.message = 'Rate limited by the upload service',
    this.error,
  });

  @override
  final String message;
  @override
  Object? error;
}

/// A direct-to-network transaction whose header the gateway refused, so the
/// transaction never reached the network: nothing was posted or paid for.
class TransactionHeaderNotPostedException implements ArDriveUploaderExceptions {
  TransactionHeaderNotPostedException({this.error});

  @override
  String get message => 'The transaction header was not posted';
  @override
  final Object? error;

  @override
  String toString() =>
      'TransactionHeaderNotPostedException: $message. Error: $error';
}

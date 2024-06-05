abstract class ArDriveUploaderExceptions {
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

class MetadataUploadException implements UploadStrategyException {
  MetadataUploadException({
    required this.message,
    this.error,
  });

  @override
  final String message;
  @override
  Object? error;
}

class DataUploadException implements UploadStrategyException {
  DataUploadException({
    required this.message,
    this.error,
  });

  @override
  final String message;
  @override
  Object? error;
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

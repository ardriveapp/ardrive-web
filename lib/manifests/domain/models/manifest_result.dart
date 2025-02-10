import 'package:ardrive/manifests/domain/entities/manifest.dart';
import 'package:equatable/equatable.dart';

/// Represents the result of fetching a manifest.
/// Can be either a success with the manifest data or a failure with an error.
class ManifestResult extends Equatable {
  final Manifest? manifest;
  final ManifestFailure? failure;

  const ManifestResult.success(Manifest this.manifest) : failure = null;

  const ManifestResult.failure(ManifestFailure this.failure) : manifest = null;

  bool get isSuccess => manifest != null;
  bool get isFailure => failure != null;

  @override
  List<Object?> get props => [manifest, failure];
}

/// Base class for manifest-related failures.
abstract class ManifestFailure extends Equatable {
  final String message;

  const ManifestFailure(this.message);

  @override
  List<Object> get props => [message];
}

/// Indicates that the manifest data is invalid or could not be parsed.
class InvalidManifestFailure extends ManifestFailure {
  const InvalidManifestFailure(super.message);
}

/// Indicates that there was a network error while fetching the manifest.
class NetworkFailure extends ManifestFailure {
  const NetworkFailure(super.message);
}

/// Indicates that the manifest could not be found.
class NotFoundFailure extends ManifestFailure {
  const NotFoundFailure(super.message);
}

import 'package:equatable/equatable.dart';

abstract class ManifestFailure extends Equatable {
  const ManifestFailure();

  @override
  List<Object?> get props => [];
}

class InvalidManifestFailure extends ManifestFailure {
  final String message;

  const InvalidManifestFailure(this.message);

  @override
  List<Object?> get props => [message];
}

class NetworkFailure extends ManifestFailure {
  final String message;

  const NetworkFailure(this.message);

  @override
  List<Object?> get props => [message];
}

class NotFoundFailure extends ManifestFailure {
  const NotFoundFailure();
}

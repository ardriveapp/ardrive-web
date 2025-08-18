part of 'shared_file_cubit.dart';

@immutable
abstract class SharedFileState extends Equatable {
  const SharedFileState();

  @override
  List<Object?> get props => [];
}

class SharedFileLoadInProgress extends SharedFileState {}

class SharedFileIsPrivate extends SharedFileState {}

/// [SharedFileLoadSuccess] indicates that the shared file being viewed has been
/// loaded successfully.
class SharedFileLoadSuccess extends SharedFileState {
  final List<FileRevision> fileRevisions;
  final SecretKey? fileKey;
  final LicenseState? latestLicense;
  final String? ownerAddress;

  const SharedFileLoadSuccess({
    required this.fileRevisions,
    this.fileKey,
    this.latestLicense,
    this.ownerAddress,
  });

  @override
  List<Object?> get props => [fileRevisions, fileKey, ownerAddress];
}

class SharedFileKeyInvalid extends SharedFileState {}

class SharedFileNotFound extends SharedFileState {}

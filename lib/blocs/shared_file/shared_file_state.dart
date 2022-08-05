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

  const SharedFileLoadSuccess({required this.fileRevisions, this.fileKey});

  @override
  List<Object?> get props => [fileRevisions, fileKey];
}

class SharedFileNotFound extends SharedFileState {}

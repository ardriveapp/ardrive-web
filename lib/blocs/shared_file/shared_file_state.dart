part of 'shared_file_cubit.dart';

@immutable
abstract class SharedFileState extends Equatable {
  const SharedFileState();

  @override
  List<Object> get props => [];
}

class SharedFileLoadInProgress extends SharedFileState {}

/// [SharedFileLoadSuccess] indicates that the shared file being viewed has been
/// loaded successfully.
class SharedFileLoadSuccess extends SharedFileState {
  final FileEntity file;
  final SecretKey fileKey;
  final String dataTxId;
  final String metadataTxId;

  const SharedFileLoadSuccess({
    @required this.file,
    this.fileKey,
    this.dataTxId,
    this.metadataTxId,
  });

  @override
  List<Object> get props => [file, fileKey];
}

class SharedFileNotFound extends SharedFileState {}

part of 'shared_file_cubit.dart';

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

  const SharedFileLoadSuccess({this.file});
}

class SharedFileNotFound extends SharedFileState {}

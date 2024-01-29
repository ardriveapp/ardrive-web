part of 'sharing_file_bloc.dart';

sealed class SharingFileState extends Equatable {
  const SharingFileState();

  @override
  List<Object> get props => [];
}

final class SharingFileInitial extends SharingFileState {}

final class SharingFileReceivedState extends SharingFileState {
  final List<IOFile> files;

  const SharingFileReceivedState(this.files);

  @override
  List<Object> get props => [files];
}

final class SharingFileClearedState extends SharingFileState {
  @override
  List<Object> get props => [];
}

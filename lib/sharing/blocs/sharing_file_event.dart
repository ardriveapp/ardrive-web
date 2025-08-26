part of 'sharing_file_bloc.dart';

sealed class SharingFileEvent extends Equatable {
  const SharingFileEvent();

  @override
  List<Object> get props => [];
}

class SharingFileReceived extends SharingFileEvent {
  // final List<SharedFile> files;

  const SharingFileReceived();

  @override
  List<Object> get props => [];
}

class ResubmitSharingFile extends SharingFileEvent {}

class ShowSharingFile extends SharingFileEvent {}

class SharingFileCleared extends SharingFileEvent {}

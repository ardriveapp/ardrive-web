part of 'multi_thumbnail_creation_bloc.dart';

sealed class MultiThumbnailCreationState extends Equatable {
  const MultiThumbnailCreationState();

  @override
  List<Object> get props => [];
}

final class MultiThumbnailCreationInitial extends MultiThumbnailCreationState {}

final class MultiThumbnailCreationLoadingFiles
    extends MultiThumbnailCreationState {}

final class MultiThumbnailCreationFilesLoaded
    extends MultiThumbnailCreationState {
  final List<FileWithLatestRevisionTransactions> files;

  const MultiThumbnailCreationFilesLoaded({required this.files});

  @override
  List<Object> get props => [files];
}

final class MultiThumbnailCreationLoadingThumbnails
    extends MultiThumbnailCreationState {
  final List<ThumbnailLoadingStatus> thumbnails;
  final int loadedCount;

  const MultiThumbnailCreationLoadingThumbnails(
      {required this.thumbnails, this.loadedCount = 0});

  @override
  List<Object> get props => [UniqueKey()];
}

final class MultiThumbnailCreationFilesLoadedEmpty
    extends MultiThumbnailCreationState {}

class ThumbnailLoadingStatus {
  final FileWithLatestRevisionTransactions file;
  final bool loaded;

  const ThumbnailLoadingStatus({
    required this.file,
    required this.loaded,
  });
}

final class MultiThumbnailCreationThumbnailsLoaded
    extends MultiThumbnailCreationState {}

final class MultiThumbnailCreationCancelled
    extends MultiThumbnailCreationState {}

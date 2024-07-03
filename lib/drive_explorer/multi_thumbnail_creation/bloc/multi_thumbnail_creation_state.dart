part of 'multi_thumbnail_creation_bloc.dart';

sealed class MultiThumbnailCreationState extends Equatable {
  const MultiThumbnailCreationState();

  @override
  List<Object?> get props => [];
}

final class MultiThumbnailCreationInitial extends MultiThumbnailCreationState {}

final class MultiThumbnailCreationLoadingFiles
    extends MultiThumbnailCreationState {}

// final class MultiThumbnailCreationFilesLoaded
//     extends MultiThumbnailCreationState {
//   final List<FileWithLatestRevisionTransactions> files;

//   const MultiThumbnailCreationFilesLoaded({required this.files});

//   @override
//   List<Object> get props => [files];
// }

final class MultiThumbnailCreationLoadingThumbnails
    extends MultiThumbnailCreationState {
  final List<ThumbnailLoadingStatus> thumbnailsInDrive;
  final Drive? driveInExecution;
  final int loadedDrives;
  final int loadedThumbnailsInDrive;
  final int numberOfDrives;

  const MultiThumbnailCreationLoadingThumbnails({
    required this.thumbnailsInDrive,
    this.driveInExecution,
    required this.loadedDrives,
    required this.loadedThumbnailsInDrive,
    required this.numberOfDrives,
  });

  @override
  List<Object?> get props => [
        thumbnailsInDrive,
        driveInExecution,
        loadedDrives,
        loadedThumbnailsInDrive,
        numberOfDrives,
      ];
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

final class MultiThumbnailCreationError extends MultiThumbnailCreationState {
  @override
  List<Object> get props => [];
}

part of 'multi_thumbnail_creation_bloc.dart';

sealed class MultiThumbnailCreationEvent extends Equatable {
  const MultiThumbnailCreationEvent();

  @override
  List<Object> get props => [];
}

final class CreateMultiThumbnailForAllDrives
    extends MultiThumbnailCreationEvent {
  const CreateMultiThumbnailForAllDrives();

  @override
  List<Object> get props => [];
}

// cancel
final class CancelMultiThumbnailCreation extends MultiThumbnailCreationEvent {}

final class SkipDriveMultiThumbnailCreation
    extends MultiThumbnailCreationEvent {
  const SkipDriveMultiThumbnailCreation();

  @override
  List<Object> get props => [];
}

final class CloseMultiThumbnailCreation extends MultiThumbnailCreationEvent {}

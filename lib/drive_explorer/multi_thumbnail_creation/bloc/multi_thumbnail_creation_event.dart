part of 'multi_thumbnail_creation_bloc.dart';

sealed class MultiThumbnailCreationEvent extends Equatable {
  const MultiThumbnailCreationEvent();

  @override
  List<Object> get props => [];
}

final class CreateMultiThumbnailForDrive extends MultiThumbnailCreationEvent {
  final Drive drive;

  const CreateMultiThumbnailForDrive({required this.drive});

  @override
  List<Object> get props => [drive];
}

// cancel
final class CancelMultiThumbnailCreation extends MultiThumbnailCreationEvent {}

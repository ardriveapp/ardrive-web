part of 'thumbnail_creation_bloc.dart';

sealed class ThumbnailCreationEvent extends Equatable {
  const ThumbnailCreationEvent();

  @override
  List<Object> get props => [];
}

final class CreateThumbnail extends ThumbnailCreationEvent {
  final FileDataTableItem fileDataTableItem;

  const CreateThumbnail({required this.fileDataTableItem});

  @override
  List<Object> get props => [fileDataTableItem];
}

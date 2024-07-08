part of 'thumbnail_bloc.dart';

sealed class ThumbnailEvent extends Equatable {
  const ThumbnailEvent();

  @override
  List<Object> get props => [];
}

final class GetThumbnail extends ThumbnailEvent {
  final FileDataTableItem fileDataTableItem;

  const GetThumbnail({required this.fileDataTableItem});

  @override
  List<Object> get props => [fileDataTableItem];
}

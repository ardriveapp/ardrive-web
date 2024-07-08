part of 'thumbnail_bloc.dart';

sealed class ThumbnailState extends Equatable {
  const ThumbnailState();

  @override
  List<Object> get props => [];
}

final class ThumbnailInitial extends ThumbnailState {}

final class ThumbnailLoading extends ThumbnailState {}

final class ThumbnailLoaded extends ThumbnailState {
  final ThumbnailData thumbnail;

  const ThumbnailLoaded({required this.thumbnail});

  @override
  List<Object> get props => [thumbnail];
}

final class ThumbnailError extends ThumbnailState {}

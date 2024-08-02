part of 'thumbnail_creation_bloc.dart';

sealed class ThumbnailCreationState extends Equatable {
  const ThumbnailCreationState();

  @override
  List<Object> get props => [];
}

final class ThumbnailCreationInitial extends ThumbnailCreationState {}

final class ThumbnailCreationLoading extends ThumbnailCreationState {}

final class ThumbnailCreationSuccess extends ThumbnailCreationState {}

final class ThumbnailCreationError extends ThumbnailCreationState {}

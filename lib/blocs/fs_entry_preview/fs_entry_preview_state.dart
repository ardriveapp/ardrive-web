part of 'fs_entry_preview_cubit.dart';

abstract class FsEntryPreviewState extends Equatable {
  const FsEntryPreviewState();

  @override
  List<Object> get props => [];
}

class FsEntryPreviewUnavailable extends FsEntryPreviewState {}

class FsEntryPreviewInitial extends FsEntryPreviewState {}

class FsEntryPreviewSuccess extends FsEntryPreviewState {
  final String previewUrl;

  const FsEntryPreviewSuccess({required this.previewUrl});

  @override
  List<Object> get props => [previewUrl];
}

class FsEntryPreviewLoading extends FsEntryPreviewSuccess {
  const FsEntryPreviewLoading() : super(previewUrl: '');
}

class FsEntryPreviewImage extends FsEntryPreviewSuccess {
  final Uint8List imageBytes;

  const FsEntryPreviewImage({
    required this.imageBytes,
    required String previewUrl,
  }) : super(previewUrl: previewUrl);

  @override
  List<Object> get props => [imageBytes, previewUrl];
}

class FsEntryPreviewAudio extends FsEntryPreviewSuccess {
  const FsEntryPreviewAudio({
    required String previewUrl,
  }) : super(previewUrl: previewUrl);

  @override
  List<Object> get props => [previewUrl];
}

class FsEntryPreviewVideo extends FsEntryPreviewSuccess {
  const FsEntryPreviewVideo({
    required String previewUrl,
  }) : super(previewUrl: previewUrl);

  @override
  List<Object> get props => [previewUrl];
}

class FsEntryPreviewText extends FsEntryPreviewSuccess {
  const FsEntryPreviewText({
    required String previewUrl,
  }) : super(previewUrl: previewUrl);

  @override
  List<Object> get props => [previewUrl];
}

class FsEntryPreviewFailure extends FsEntryPreviewState {}

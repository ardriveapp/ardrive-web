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

  FsEntryPreviewSuccess({required this.previewUrl});

  @override
  List<Object> get props => [previewUrl];
}

class FsEntryPreviewLoading extends FsEntryPreviewSuccess {
  FsEntryPreviewLoading() : super(previewUrl: '');
}

class FsEntryPreviewImage extends FsEntryPreviewSuccess {
  FsEntryPreviewImage({
    required String previewUrl,
  }) : super(previewUrl: previewUrl);

  @override
  List<Object> get props => [previewUrl];
}

class FsEntryPreviewPrivateImage extends FsEntryPreviewImage {
  final Uint8List imageBytes;
  FsEntryPreviewPrivateImage({
    required this.imageBytes,
    required String previewUrl,
  }) : super(previewUrl: previewUrl);

  @override
  List<Object> get props => [imageBytes, previewUrl];
}

class FsEntryPreviewAudio extends FsEntryPreviewSuccess {
  FsEntryPreviewAudio({
    required String previewUrl,
  }) : super(previewUrl: previewUrl);

  @override
  List<Object> get props => [previewUrl];
}

class FsEntryPreviewVideo extends FsEntryPreviewSuccess {
  FsEntryPreviewVideo({
    required String previewUrl,
  }) : super(previewUrl: previewUrl);

  @override
  List<Object> get props => [previewUrl];
}

class FsEntryPreviewText extends FsEntryPreviewSuccess {
  FsEntryPreviewText({
    required String previewUrl,
  }) : super(previewUrl: previewUrl);

  @override
  List<Object> get props => [previewUrl];
}

class FsEntryPreviewFailure extends FsEntryPreviewState {}

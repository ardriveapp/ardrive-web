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
  const FsEntryPreviewImage({required super.previewUrl});

  @override
  List<Object> get props => [previewUrl];
}

class FsEntryPreviewPdf extends FsEntryPreviewSuccess {
  const FsEntryPreviewPdf({required super.previewUrl});

  @override
  List<Object> get props => [previewUrl];
}

class FsEntryPreviewAudio extends FsEntryPreviewSuccess {
  final String filename;
  const FsEntryPreviewAudio(
      {required super.previewUrl, required this.filename});

  @override
  List<Object> get props => [previewUrl, filename];
}

class FsEntryPreviewVideo extends FsEntryPreviewSuccess {
  final String filename;

  const FsEntryPreviewVideo({
    required super.previewUrl,
    required this.filename,
  });

  @override
  List<Object> get props => [previewUrl, filename];
}

class FsEntryPreviewMemory extends FsEntryPreviewSuccess {
  const FsEntryPreviewMemory({
    required Uint8List memoryBytes,
  }) : super(previewUrl: '');

  @override
  List<Object> get props => [previewUrl];
}

class FsEntryPreviewText extends FsEntryPreviewSuccess {
  final String filename;
  final String content;
  final String contentType;

  const FsEntryPreviewText({
    required super.previewUrl,
    required this.filename,
    required this.content,
    required this.contentType,
  });

  @override
  List<Object> get props => [previewUrl, filename, content, contentType];
}

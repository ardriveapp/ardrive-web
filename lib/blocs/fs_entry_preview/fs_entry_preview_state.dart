part of 'fs_entry_preview_cubit.dart';

abstract class FsEntryPreviewState extends Equatable {
  const FsEntryPreviewState();

  @override
  List<Object> get props => [];
}

class FsEntryPreviewUnavailable extends FsEntryPreviewState {}

/// The file is too large to buffer into memory for an in-app preview, so its
/// bytes are never fetched.
///
/// Extends [FsEntryPreviewUnavailable] on purpose: every existing
/// `is FsEntryPreviewUnavailable` consumer keeps behaving as it does today
/// until the preview widget renders a dedicated oversized message.
class FsEntryPreviewOversized extends FsEntryPreviewUnavailable {
  final int fileSize;
  final int maxFileSize;

  FsEntryPreviewOversized({
    required this.fileSize,
    required this.maxFileSize,
  });

  @override
  List<Object> get props => [fileSize, maxFileSize];
}

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

/// A PDF that can be opened outside the app.
///
/// [previewUrl] is a gateway URL for the *public* bytes of the file, and is
/// only ever emitted for a file whose bytes are public: it is opened in a new
/// tab, where the browser's own PDF viewer renders it on the gateway's origin
/// rather than on this one. Nothing is rendered inline, because a PDF can carry
/// JavaScript and `docs/FILE_SHARING_REDESIGN_PLAN.md` §4.3 forbids bytes from
/// an untrusted transaction becoming script-capable content on the app origin.
class FsEntryPreviewPdf extends FsEntryPreviewSuccess {
  final String filename;

  const FsEntryPreviewPdf({
    required super.previewUrl,
    required this.filename,
  });

  @override
  List<Object> get props => [previewUrl, filename];
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
  final FileDataTableItem fileItem;

  const FsEntryPreviewText({
    required super.previewUrl,
    required this.filename,
    required this.content,
    required this.contentType,
    required this.fileItem,
  });

  @override
  List<Object> get props => [previewUrl, filename, content, contentType, fileItem];
}

class FsEntryPreviewEmail extends FsEntryPreviewSuccess {
  final String filename;
  final ParsedEmail email;

  const FsEntryPreviewEmail({
    required super.previewUrl,
    required this.filename,
    required this.email,
  });

  @override
  List<Object> get props => [previewUrl, filename, email];
}

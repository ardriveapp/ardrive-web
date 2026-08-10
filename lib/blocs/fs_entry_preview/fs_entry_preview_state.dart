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

/// A PDF, as plaintext bytes this app rasterises itself.
///
/// [pdfBytes] is the *plaintext* of the file - fetched through the gateway
/// waterfall for a public file, fetched and decrypted in memory for a private
/// one - and is turned into page images by a rasteriser and painted as ordinary
/// Flutter widgets. It is never handed to an `<iframe>`, `<embed>`, `<object>`
/// or a blob URL: a PDF can carry JavaScript, and
/// `docs/FILE_SHARING_REDESIGN_PLAN.md` §4.3 forbids bytes from an untrusted
/// transaction becoming script-capable content on this origin - load-bearing,
/// because a recipient's access key can be sitting in this origin's
/// `sessionStorage`. Rasterising keeps the posture of the image preview: decode
/// the bytes, paint the result, run nothing.
///
/// `null` when the bytes could not be had, which is not fatal for a public file
/// - see [canOpenOnGateway].
///
/// [previewUrl] only means anything when [canOpenOnGateway] is set: a *public*
/// file's bytes have a URL of their own, so a viewer that cannot render them
/// can still offer to open them in a new tab, on the gateway's origin. A
/// private file has no such URL - every gateway holds only its ciphertext - and
/// gets no such offer.
class FsEntryPreviewPdf extends FsEntryPreviewSuccess {
  final String filename;
  final Uint8List? pdfBytes;
  final bool canOpenOnGateway;

  const FsEntryPreviewPdf({
    required super.previewUrl,
    required this.filename,
    this.pdfBytes,
    this.canOpenOnGateway = false,
  });

  @override
  List<Object> get props => [
        previewUrl,
        filename,
        canOpenOnGateway,
        pdfBytes ?? const <int>[],
      ];
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

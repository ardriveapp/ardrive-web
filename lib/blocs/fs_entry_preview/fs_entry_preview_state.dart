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

/// Which player a media preview will play in.
enum FsEntryPreviewMediaKind { video, audio }

/// What a not-yet-playing media preview needs to draw its player's frame: the
/// kind of player, and the file's name under it.
///
/// Carried by [FsEntryPreviewLoading], [FsEntryPreviewOnRequest] and
/// [FsEntryPreviewFailed] when the preview is media, so those states are drawn
/// inside the player that will play the file instead of on the panel behind
/// it - and the player's frame stands from the first moment to the last.
class FsEntryPreviewMedia extends Equatable {
  const FsEntryPreviewMedia({required this.kind, required this.filename});

  final FsEntryPreviewMediaKind kind;
  final String filename;

  @override
  List<Object> get props => [kind, filename];
}

/// What a buffered preview is doing while the reader waits.
enum FsEntryPreviewLoadPhase {
  /// The bytes are on their way, and [FsEntryPreviewLoading.received] counts
  /// them.
  downloading,

  /// The bytes are here and being decrypted. One opaque call over the whole
  /// buffer, so there is no progress to report - and none is faked.
  decrypting,
}

/// A preview that is not on screen yet, and how far it has got.
///
/// A private file of tens of MiB used to sit behind a bare spinner for as long
/// as it took to arrive (#2206). It read as frozen, and the natural response -
/// a refresh - threw the download away and started it over. This carries what
/// the reader needs to see that it is working.
class FsEntryPreviewLoading extends FsEntryPreviewSuccess {
  const FsEntryPreviewLoading({
    this.phase = FsEntryPreviewLoadPhase.downloading,
    this.received = 0,
    this.total,
    this.media,
  }) : super(previewUrl: '');

  /// Set when the file will play in a media player. See [FsEntryPreviewMedia].
  final FsEntryPreviewMedia? media;

  final FsEntryPreviewLoadPhase phase;

  /// Bytes received so far from the gateway answering now.
  final int received;

  /// What that gateway declared it would send, or null when it did not say.
  final int? total;

  /// How much of the download is done, from 0 to 1, or null when that cannot
  /// be known: no declared length, or not downloading any more.
  double? get fraction {
    final total = this.total;

    if (phase != FsEntryPreviewLoadPhase.downloading ||
        total == null ||
        total <= 0) {
      return null;
    }

    return (received / total).clamp(0.0, 1.0);
  }

  @override
  List<Object> get props => [
        phase,
        received,
        total ?? -1,
        if (media != null) media!,
      ];
}

/// A preview big enough that it waits to be asked for.
///
/// Every preview that downloads the whole file - a PDF, private media, an
/// image - used to start the moment the file was selected, up to 100 MiB of
/// it. Above [FsEntryPreviewCubit.previewOnRequestSize] it now waits for the
/// reader to press Preview, so selecting a large file costs nothing until they
/// do. Like [FsEntryPreviewFailed], deliberately not an
/// [FsEntryPreviewUnavailable]: the preview is offered, not withheld.
class FsEntryPreviewOnRequest extends FsEntryPreviewState {
  const FsEntryPreviewOnRequest({required this.size, this.media});

  /// How much pressing Preview will download.
  final int size;

  /// Set when the file will play in a media player. See [FsEntryPreviewMedia].
  final FsEntryPreviewMedia? media;

  @override
  List<Object> get props => [size, if (media != null) media!];
}

/// Why a preview that was attempted did not arrive.
enum FsEntryPreviewFailure {
  /// No gateway would give the bytes, or what the file is encrypted with could
  /// not be looked up. Worth asking again.
  download,

  /// The bytes arrived and would not decrypt. Asking again fetches the same
  /// bytes; the file may still download and open elsewhere.
  decrypt,
}

/// A preview that was attempted and failed - as against one that is not
/// offered at all.
///
/// Deliberately *not* an [FsEntryPreviewUnavailable]. That state means "this
/// kind of file is not previewed here", and every consumer that checks for it
/// hides the preview: the details panel drops its Preview tab, the share page
/// says the type is unsupported. A failure is neither of those. It keeps its
/// place on screen, says what went wrong, and offers Retry when asking again
/// could help.
class FsEntryPreviewFailed extends FsEntryPreviewState {
  const FsEntryPreviewFailed(this.reason, {this.media});

  final FsEntryPreviewFailure reason;

  /// Set when the file would have played in a media player. See
  /// [FsEntryPreviewMedia].
  final FsEntryPreviewMedia? media;

  bool get canRetry => reason == FsEntryPreviewFailure.download;

  @override
  List<Object> get props => [reason, if (media != null) media!];
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
  List<Object> get props =>
      [previewUrl, filename, content, contentType, fileItem];
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

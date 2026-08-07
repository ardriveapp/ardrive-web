part of 'file_download_cubit.dart';

abstract class FileDownloadState extends Equatable {
  const FileDownloadState();

  @override
  List<Object> get props => [];
}

class FileDownloadStarting extends FileDownloadState {}

class FileDownloadInProgress extends FileDownloadState {
  const FileDownloadInProgress({
    required this.fileName,
    required this.totalByteCount,
  });

  final String fileName;
  final int totalByteCount;

  @override
  List<Object> get props => [fileName, totalByteCount];
}

class FileDownloadWithProgress extends FileDownloadState {
  const FileDownloadWithProgress({
    required this.fileName,
    required this.progress,
    required this.fileSize,
    required this.contentType,
    this.isReconnecting = false,
  });

  final int progress;
  final int fileSize;
  final String fileName;
  final String contentType;

  /// Whether the transport dropped and the download is picking itself back up
  /// from the last byte it delivered.
  ///
  /// The bar does not move while this is set, because no bytes are arriving.
  /// Saying so is the whole point: a bar that has stopped without explanation
  /// is indistinguishable from a hung app.
  final bool isReconnecting;

  /// The same progress, now waiting on a reconnect.
  ///
  /// A resume arrives on its own stream rather than as a progress tick, so the
  /// only thing that changes is this flag — which is why it is in [props].
  /// Without it the emit is a duplicate state and the cubit drops it.
  FileDownloadWithProgress asReconnecting() => FileDownloadWithProgress(
        fileName: fileName,
        progress: progress,
        fileSize: fileSize,
        contentType: contentType,
        isReconnecting: true,
      );

  @override
  List<Object> get props => [progress, fileName, isReconnecting];
}

/// Every byte is saved, and the integrity check has not answered yet.
///
/// Only ever visible when the check outlives the save, which is the streaming
/// case: an AES-GCM file is authenticated before a byte is written, so its
/// verdict is already in and this state passes without ever being painted.
class FileDownloadVerifying extends FileDownloadState {
  const FileDownloadVerifying({required this.fileName});

  final String fileName;

  @override
  List<Object> get props => [fileName];
}

class FileDownloadFinishedWithSuccess extends FileDownloadState {
  const FileDownloadFinishedWithSuccess({
    required this.fileName,
    this.integrity,
  });

  final String fileName;

  /// What the integrity check made of the bytes that were saved, or `null` when
  /// no check was run at all.
  ///
  /// The three verdicts are not two: [DataItemIntegrityVerdict.notVerified] is
  /// the routine "nothing to compare against" answer — a resumed download, a
  /// file signed with a wallet ArDrive cannot check — and is never evidence of
  /// a problem. Only [DataItemIntegrityVerdict.failed] means the bytes
  /// contradict what was signed.
  ///
  /// `null` and `notVerified` are deliberately different. `null` is the mobile
  /// public download, which never asks; it says nothing rather than reporting
  /// an absence of something it never looked for.
  final DataItemIntegrityVerdict? integrity;

  @override
  List<Object> get props => [fileName, integrity ?? 'no check was run'];
}

class FileDownloadSuccess extends FileDownloadState {
  const FileDownloadSuccess(
      {required this.fileName,
      required this.bytes,
      this.mimeType,
      required this.lastModified});

  final String fileName;
  final String? mimeType;
  final Uint8List bytes;
  final DateTime lastModified;

  @override
  List<Object> get props => [fileName];
}

class FileDownloadFailure extends FileDownloadState {
  const FileDownloadFailure(this.reason);

  final FileDownloadFailureReason reason;
}

class FileDownloadWarning extends FileDownloadState {
  const FileDownloadWarning();
}

class FileDownloadAborted extends FileDownloadState {}

enum FileDownloadFailureReason {
  unknownError,
  fileAboveLimit,
  browserDoesNotSupportLargeDownloads,
  networkConnectionError,
  fileNotFound,
  rateLimited,

  /// The connection dropped and could not be picked up where it left off, so
  /// the part that had already arrived is gone
  /// ([DownloadResumeNotSupportedException]). Retrying is the right offer and
  /// it works — it just starts from the beginning, which the dialog for this
  /// reason has to say rather than implying the download carries on.
  downloadMustRestart,

  /// The bytes kept coming past the size the file claimed, so the download
  /// could not be held in memory long enough to check its authentication tag
  /// and was stopped. Nothing was written. Retrying is pointless: the file's
  /// metadata and its data disagree.
  fileTooLargeToVerify,

  /// The bytes that arrived are not the bytes that were signed - an AES-GCM
  /// authentication tag that did not match (§3.1). **Nothing was written**,
  /// and retrying cannot help: the same bytes would fail the same check. The
  /// dialog for this one therefore offers no "Try again".
  integrityCheckFailed,
}

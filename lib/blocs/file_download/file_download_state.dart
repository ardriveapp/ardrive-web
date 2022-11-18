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
  });

  final int progress;
  final int fileSize;
  final String fileName;

  @override
  List<Object> get props => [progress, fileName];
}

class FileDownloadFinishedWithSuccess extends FileDownloadState {
  const FileDownloadFinishedWithSuccess({
    required this.fileName,
  });

  final String fileName;

  @override
  List<Object> get props => [fileName];
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

enum FileDownloadFailureReason { unknownError, fileAboveLimit }

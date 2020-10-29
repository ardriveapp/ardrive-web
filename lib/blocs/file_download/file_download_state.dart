part of 'file_download_cubit.dart';

abstract class FileDownloadState extends Equatable {
  const FileDownloadState();

  @override
  List<Object> get props => [];
}

class FileDownloadStarting extends FileDownloadState {}

class FileDownloadInProgress extends FileDownloadState {
  final String fileName;
  final double downloadProgress;
  final int downloadedByteCount;
  final int totalByteCount;

  FileDownloadInProgress({
    @required this.fileName,
    this.downloadProgress = 0,
    this.downloadedByteCount = 0,
    this.totalByteCount = 0,
  });

  @override
  List<Object> get props =>
      [fileName, downloadProgress, downloadedByteCount, totalByteCount];
}

class FileDownloadSuccess extends FileDownloadState {
  final String fileName;
  final String fileExtension;
  final Uint8List fileDataBytes;

  FileDownloadSuccess({
    @required this.fileName,
    @required this.fileExtension,
    @required this.fileDataBytes,
  });

  @override
  List<Object> get props => [fileName, fileExtension, fileDataBytes];
}

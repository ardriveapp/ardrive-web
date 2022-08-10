part of 'file_download_cubit.dart';

abstract class FileDownloadState extends Equatable {
  const FileDownloadState();

  @override
  List<Object> get props => [];
}

class FileDownloadStarting extends FileDownloadState {}

class FileDownloadInProgress extends FileDownloadState {
  final String fileName;
  final int totalByteCount;

  const FileDownloadInProgress({
    required this.fileName,
    required this.totalByteCount,
  });

  @override
  List<Object> get props => [fileName, totalByteCount];
}

class FileDownloadSuccess extends FileDownloadState {
  final XFile file;

  const FileDownloadSuccess({
    required this.file,
  });

  @override
  List<Object> get props => [file];
}

class FileDownloadFailure extends FileDownloadState {}

class FileDownloadAborted extends FileDownloadState {}

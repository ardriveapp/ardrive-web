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

  FileDownloadInProgress({
    @required this.fileName,
    this.totalByteCount,
  });

  @override
  List<Object> get props => [fileName, totalByteCount];
}

class FileDownloadSuccess extends FileDownloadState {
  final XFile file;

  FileDownloadSuccess({
    @required this.file,
  });

  @override
  List<Object> get props => [file];
}

class FileDownloadFailure extends FileDownloadState {}

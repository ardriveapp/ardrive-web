part of 'file_download_cubit.dart';

abstract class FileDownloadState extends Equatable {
  const FileDownloadState();

  @override
  List<Object> get props => [];
}

class FileDownloadInProgress extends FileDownloadState {}

class FileDownloadSuccess extends FileDownloadState {
  final String fileName;
  final String fileExtension;
  final Uint8List fileDataBytes;

  FileDownloadSuccess(
      {@required this.fileName,
      @required this.fileExtension,
      @required this.fileDataBytes});

  @override
  List<Object> get props => [fileName, fileExtension, fileDataBytes];
}

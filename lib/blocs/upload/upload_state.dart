part of 'upload_cubit.dart';

@immutable
abstract class UploadState extends Equatable {
  @override
  List<Object> get props => [];
}

class UploadPreparationInProgress extends UploadState {}

class UploadFileAlreadyExists extends UploadState {
  final String fileName;

  UploadFileAlreadyExists({@required this.fileName});

  @override
  List<Object> get props => [fileName];
}

class UploadFileReady extends UploadState {
  final String fileName;
  final BigInt uploadCost;
  final int uploadSize;

  UploadFileReady({
    @required this.fileName,
    @required this.uploadCost,
    @required this.uploadSize,
  });

  @override
  List<Object> get props => [fileName, uploadCost, uploadSize];
}

class UploadFileInProgress extends UploadState {
  final String fileName;
  final int fileSize;

  final double uploadProgress;
  final int uploadedFileSize;

  UploadFileInProgress({
    @required this.fileName,
    @required this.fileSize,
    this.uploadProgress = 0,
    this.uploadedFileSize = 0,
  });

  @override
  List<Object> get props => [fileName, uploadProgress];
}

class UploadFolderInProgress extends UploadState {
  final List<UploadFileInProgress> fileUploads;

  UploadFolderInProgress({@required this.fileUploads});

  @override
  List<Object> get props => [fileUploads];
}

class UploadComplete extends UploadState {}

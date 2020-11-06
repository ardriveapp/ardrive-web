part of 'upload_cubit.dart';

@immutable
abstract class UploadState extends Equatable {
  @override
  List<Object> get props => [];
}

class UploadPreparationInProgress extends UploadState {}

class UploadPreparationFailure extends UploadState {}

class UploadFileAlreadyExists extends UploadState {
  final String existingFileId;
  final String existingFileName;

  UploadFileAlreadyExists({
    @required this.existingFileId,
    @required this.existingFileName,
  });

  @override
  List<Object> get props => [existingFileId, existingFileName];
}

class UploadFileReady extends UploadState {
  final String fileName;
  final BigInt uploadCost;
  final int uploadSize;

  final bool insufficientArBalance;

  UploadFileReady({
    @required this.fileName,
    @required this.uploadCost,
    @required this.uploadSize,
    @required this.insufficientArBalance,
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

class UploadFileFailure extends UploadState {}

class UploadFolderInProgress extends UploadState {
  final List<UploadFileInProgress> fileUploads;

  UploadFolderInProgress({@required this.fileUploads});

  @override
  List<Object> get props => [fileUploads];
}

class UploadComplete extends UploadState {}

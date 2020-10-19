part of 'upload_cubit.dart';

@immutable
abstract class UploadState {}

class UploadIdle extends UploadState {}

class UploadPreparationInProgress extends UploadState {}

class UploadFileAlreadyExists extends UploadState {
  final String fileName;

  UploadFileAlreadyExists({this.fileName});
}

class UploadFileReady extends UploadState {
  final String fileName;
  final BigInt uploadCost;
  final int uploadSize;

  UploadFileReady({
    this.fileName,
    this.uploadCost,
    this.uploadSize,
  });
}

class UploadInProgress extends UploadState {}

class UploadComplete extends UploadState {}

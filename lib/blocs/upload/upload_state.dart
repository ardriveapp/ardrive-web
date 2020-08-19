part of 'upload_bloc.dart';

@immutable
abstract class UploadState {}

class UploadIdle extends UploadState {}

class UploadBeingPrepared extends UploadState {}

class UploadFileReady extends UploadState {
  final String fileId;
  final String fileName;
  final BigInt uploadCost;
  final int uploadSize;
  final UploadFileToNetwork fileUploadHandle;

  UploadFileReady(
    this.fileId,
    this.fileName,
    this.uploadCost,
    this.uploadSize,
    this.fileUploadHandle,
  );
}

part of 'upload_bloc.dart';

@immutable
abstract class UploadState {}

class UploadInitial extends UploadState {}

class FileUploadReady extends UploadState {
  final String fileId;
  final String fileName;
  final BigInt uploadCost;
  final int uploadSize;
  final UploadFileToNetwork fileUploadHandle;

  FileUploadReady(
    this.fileId,
    this.fileName,
    this.uploadCost,
    this.uploadSize,
    this.fileUploadHandle,
  );
}

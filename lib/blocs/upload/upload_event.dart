part of 'upload_bloc.dart';

@immutable
abstract class UploadEvent {}

class PrepareFileUpload extends UploadEvent {
  final String driveId;
  final String parentFolderId;
  final String fileName;
  final String filePath;
  final int fileSize;
  final Uint8List fileStream;

  PrepareFileUpload(
    this.driveId,
    this.parentFolderId,
    this.fileName,
    this.filePath,
    this.fileSize,
    this.fileStream,
  );
}

class UploadFileToNetwork extends UploadEvent {
  final String fileId;
  final String driveId;
  final String parentFolderId;
  final String fileName;
  final String filePath;
  final String fileDataTxId;
  final int fileSize;
  final List<Transaction> transactions;

  UploadFileToNetwork(
    this.fileId,
    this.driveId,
    this.parentFolderId,
    this.fileName,
    this.filePath,
    this.fileDataTxId,
    this.fileSize,
    this.transactions,
  );
}

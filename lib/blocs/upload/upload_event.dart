part of 'upload_bloc.dart';

@immutable
abstract class UploadEvent {}

class PrepareFileUpload extends UploadEvent {
  final FileEntity fileEntity;
  final String filePath;
  final Uint8List fileStream;
  final SecretKey driveKey;

  PrepareFileUpload(
    this.fileEntity,
    this.filePath,
    this.fileStream, [
    this.driveKey,
  ]);
}

class UploadFileToNetwork extends UploadEvent {
  final FileEntity fileEntity;
  final String filePath;
  final List<Transaction> uploadTransactions;

  UploadFileToNetwork(
    this.fileEntity,
    this.filePath,
    this.uploadTransactions,
  );
}

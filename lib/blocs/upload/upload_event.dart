part of 'upload_bloc.dart';

@immutable
abstract class UploadEvent {}

class UploadFileToNetwork extends UploadEvent {
  final String driveId;
  final String parentFolderId;
  final String fileName;
  final String filePath;
  final int fileSize;
  final Uint8List fileStream;

  UploadFileToNetwork(
    this.driveId,
    this.parentFolderId,
    this.fileName,
    this.filePath,
    this.fileSize,
    this.fileStream,
  );
}

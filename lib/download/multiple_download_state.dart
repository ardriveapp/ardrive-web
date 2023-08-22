part of 'multiple_download_bloc.dart';

abstract class MultipleDownloadState extends Equatable {
  const MultipleDownloadState();

  @override
  List<Object> get props => [];
}

class MultipleDownloadInitial extends MultipleDownloadState {}

class MultipleDownloadInProgress extends MultipleDownloadState {
  final List<ARFSFileEntity> files;
  final int currentFileIndex;

  const MultipleDownloadInProgress({
    required this.files,
    required this.currentFileIndex,
  });

  @override
  List<Object> get props => [files, currentFileIndex];
}

class MultipleDownloadWarning extends MultipleDownloadState {}

class MultipleDownloadFailure extends MultipleDownloadState {
  final FileDownloadFailureReason reason;

  const MultipleDownloadFailure(this.reason);

  @override
  List<Object> get props => [reason];
}

class MultipleDownloadFinishedWithSuccess extends MultipleDownloadState {
  const MultipleDownloadFinishedWithSuccess(
      {required this.fileName,
      required this.bytes,
      required this.lastModified});

  final String fileName;
  final Uint8List bytes;
  final DateTime lastModified;

  @override
  List<Object> get props => [fileName, bytes, lastModified];
}

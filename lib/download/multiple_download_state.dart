part of 'multiple_download_bloc.dart';

abstract class MultipleDownloadState extends Equatable {
  const MultipleDownloadState();

  @override
  List<Object> get props => [];
}

class MultipleDownloadInitial extends MultipleDownloadState {}

class MultipleDownloadInProgress extends MultipleDownloadState {
  final List<MultiDownloadItem> files;
  final int currentFileIndex;

  const MultipleDownloadInProgress({
    required this.files,
    required this.currentFileIndex,
  });

  /// How many files the zip will hold, as the confirmation counted them.
  /// [files] also holds the folder entries, which are not downloads.
  int get fileCount => files.whereType<MultiDownloadFile>().length;

  /// The file being fetched, counted among files from 1. On a folder entry,
  /// the next file, and never more than [fileCount].
  int get currentFileNumber => math.min(
        files.take(currentFileIndex).whereType<MultiDownloadFile>().length + 1,
        fileCount,
      );

  @override
  List<Object> get props => [files, currentFileIndex];
}

class MultipleDownloadWarning extends MultipleDownloadState {}

/// What the zip will hold, before any of it is fetched (see
/// [StartDownload.confirmFirst]).
class MultipleDownloadReady extends MultipleDownloadState {
  const MultipleDownloadReady({
    required this.fileCount,
    required this.totalSize,
    required this.fileName,
  });

  final int fileCount;
  final int totalSize;
  final String fileName;

  @override
  List<Object> get props => [fileCount, totalSize, fileName];
}

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
      required this.lastModified,
      required this.skippedFiles});

  final String fileName;
  final Uint8List bytes;
  final DateTime lastModified;
  final List<MultiDownloadItem> skippedFiles;

  @override
  List<Object> get props => [fileName, bytes, lastModified, skippedFiles];
}

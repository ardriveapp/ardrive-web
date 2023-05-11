part of 'multiple_download_bloc.dart';

abstract class MultipleDownloadState extends Equatable {
  const MultipleDownloadState();

  @override
  List<Object> get props => [];
}

class MultipleDownloadInitial extends MultipleDownloadState {}

class MultipleDownloadInProgress extends MultipleDownloadState {
  final String fileName;
  final int totalByteCount;

  const MultipleDownloadInProgress({
    required this.fileName,
    required this.totalByteCount,
  });

  @override
  List<Object> get props => [fileName, totalByteCount];
}

class MultipleDownloadWarning extends MultipleDownloadState {}

class MultipleDownloadFailure extends MultipleDownloadState {
  final FileDownloadFailureReason reason;

  const MultipleDownloadFailure(this.reason);

  @override
  List<Object> get props => [reason];
}

class MultipleDownloadFinishedWithSuccess extends MultipleDownloadState {
  final String title;

  const MultipleDownloadFinishedWithSuccess({required this.title});

  @override
  List<Object> get props => [title];
}

// zipping your files
class MultipleDownloadZippingFiles extends MultipleDownloadState {
  const MultipleDownloadZippingFiles();

  @override
  List<Object> get props => [];
}

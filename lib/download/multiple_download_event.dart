part of 'multiple_download_bloc.dart';

abstract class MultipleDownloadEvent extends Equatable {
  const MultipleDownloadEvent();

  @override
  List<Object> get props => [];
}

class StartDownload extends MultipleDownloadEvent {
  final List<ArDriveDataTableItem> selectedItems;
  final String? zipName;

  const StartDownload(this.selectedItems, {this.zipName});

  @override
  List<Object> get props => [selectedItems];
}

class ResumeDownload extends MultipleDownloadEvent {
  const ResumeDownload();
}

class SkipFileAndResumeDownload extends MultipleDownloadEvent {
  const SkipFileAndResumeDownload();
}

class CancelDownload extends MultipleDownloadEvent {
  const CancelDownload();
}

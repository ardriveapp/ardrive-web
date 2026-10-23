part of 'multiple_download_bloc.dart';

abstract class MultipleDownloadEvent extends Equatable {
  const MultipleDownloadEvent();

  @override
  List<Object> get props => [];
}

class StartDownload extends MultipleDownloadEvent {
  final List<ArDriveDataTableItem> selectedItems;
  final String? zipName;

  /// Stop at [MultipleDownloadReady], saying what the zip will hold, until
  /// [ConfirmDownload]. A library page asks: its visitor does not know how
  /// large what they are about to download is.
  final bool confirmFirst;

  const StartDownload(
    this.selectedItems, {
    this.zipName,
    this.confirmFirst = false,
  });

  @override
  List<Object> get props => [selectedItems];
}

/// Go ahead from [MultipleDownloadReady].
class ConfirmDownload extends MultipleDownloadEvent {
  const ConfirmDownload();
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

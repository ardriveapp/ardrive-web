part of 'multiple_download_bloc.dart';

abstract class MultipleDownloadEvent extends Equatable {
  const MultipleDownloadEvent();

  @override
  List<Object> get props => [];
}

class StartDownload extends MultipleDownloadEvent {
  final List<ARFSFileEntity> items;

  const StartDownload(this.items);

  @override
  List<Object> get props => [items];
}

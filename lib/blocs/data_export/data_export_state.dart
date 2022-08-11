part of 'data_export_cubit.dart';

abstract class DataExportState extends Equatable {
  const DataExportState();

  @override
  List<Object> get props => [];
}

class DataExportInitial extends DataExportState {}

class DataExportInProgress extends DataExportState {
  const DataExportInProgress();

  @override
  List<Object> get props => [];
}

class DataExportSuccess extends DataExportState {
  const DataExportSuccess(
      {required this.fileName,
      required this.bytes,
      required this.mimeType,
      required this.lastModified});

  final String fileName;
  final String mimeType;
  final Uint8List bytes;
  final DateTime lastModified;

  @override
  List<Object> get props => [fileName];
}

class DataExportFailure extends DataExportState {}

class DataExportAborted extends DataExportState {}

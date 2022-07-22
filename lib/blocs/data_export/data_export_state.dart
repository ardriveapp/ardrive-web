part of 'data_export_cubit.dart';

abstract class DataExportState extends Equatable {
  const DataExportState();

  @override
  List<Object> get props => [];
}

class DataExportInitial extends DataExportState {}

class DataExportInProgress extends DataExportState {
  DataExportInProgress();

  @override
  List<Object> get props => [];
}

class DataExportSuccess extends DataExportState {
  final XFile file;
  final String fileName;

  DataExportSuccess({required this.file, required this.fileName});

  @override
  List<Object> get props => [file];
}

class DataExportFailure extends DataExportState {}

class DataExportAborted extends DataExportState {}

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
  final PlatformFile file;

  DataExportSuccess({
    required this.file,
  });

  @override
  List<Object> get props => [file];
}

class DataExportFailure extends DataExportState {}

class DataExportAborted extends DataExportState {}

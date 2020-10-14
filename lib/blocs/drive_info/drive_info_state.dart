part of 'drive_info_cubit.dart';

abstract class DriveInfoState extends Equatable {
  const DriveInfoState();

  @override
  List<Object> get props => [];
}

class DriveInfoLoadInProgress extends DriveInfoState {}

abstract class DriveInfoGeneralLoadSuccess extends DriveInfoState {
  final String name;
  final DateTime lastUpdated;
  final DateTime dateCreated;

  DriveInfoGeneralLoadSuccess({this.name, this.lastUpdated, this.dateCreated});

  @override
  List<Object> get props => [name, lastUpdated, dateCreated];
}

class DriveInfoDriveLoadSuccess extends DriveInfoGeneralLoadSuccess {
  final Drive drive;

  DriveInfoDriveLoadSuccess({
    String name,
    DateTime lastUpdated,
    DateTime dateCreated,
    this.drive,
  }) : super(name: name, lastUpdated: lastUpdated, dateCreated: dateCreated);

  @override
  List<Object> get props => [name, lastUpdated, dateCreated, drive];
}

class DriveInfoFolderLoadSuccess extends DriveInfoGeneralLoadSuccess {
  final FolderEntry folder;

  DriveInfoFolderLoadSuccess(
      {String name, DateTime lastUpdated, DateTime dateCreated, this.folder})
      : super(name: name, lastUpdated: lastUpdated, dateCreated: dateCreated);

  @override
  List<Object> get props => [name, lastUpdated, dateCreated, folder];
}

class DriveInfoFileLoadSuccess extends DriveInfoGeneralLoadSuccess {
  final FileEntry file;

  DriveInfoFileLoadSuccess(
      {String name, DateTime lastUpdated, DateTime dateCreated, this.file})
      : super(name: name, lastUpdated: lastUpdated, dateCreated: dateCreated);

  @override
  List<Object> get props => [name, lastUpdated, dateCreated, file];
}

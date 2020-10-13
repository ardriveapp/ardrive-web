part of 'drive_info_cubit.dart';

abstract class DriveInfoState extends Equatable {
  const DriveInfoState();

  @override
  List<Object> get props => [];
}

class DriveInfoLoadInProgress extends DriveInfoState {}

abstract class DriveInfoGeneralLoadSuccess extends DriveInfoState {
  final String name;

  DriveInfoGeneralLoadSuccess({this.name});

  @override
  List<Object> get props => [name];
}

class DriveInfoDriveLoadSuccess extends DriveInfoGeneralLoadSuccess {
  final Drive drive;

  DriveInfoDriveLoadSuccess({String name, this.drive}) : super(name: name);

  @override
  List<Object> get props => [name, drive];
}

class DriveInfoFolderLoadSuccess extends DriveInfoGeneralLoadSuccess {
  final FolderEntry folder;

  DriveInfoFolderLoadSuccess({String name, this.folder}) : super(name: name);

  @override
  List<Object> get props => [name, folder];
}

class DriveInfoFileLoadSuccess extends DriveInfoGeneralLoadSuccess {
  final FileEntry file;

  DriveInfoFileLoadSuccess({String name, this.file}) : super(name: name);

  @override
  List<Object> get props => [name, file];
}

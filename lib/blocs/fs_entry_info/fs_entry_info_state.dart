part of 'fs_entry_info_cubit.dart';

abstract class FsEntryInfoState extends Equatable {
  const FsEntryInfoState();

  @override
  List<Object> get props => [];
}

class FsEntryLoadInProgress extends FsEntryInfoState {}

abstract class FsEntryGeneralLoadSuccess extends FsEntryInfoState {
  final String name;
  final DateTime lastUpdated;
  final DateTime dateCreated;

  FsEntryGeneralLoadSuccess({this.name, this.lastUpdated, this.dateCreated});

  @override
  List<Object> get props => [name, lastUpdated, dateCreated];
}

class FsEntryDriveLoadSuccess extends FsEntryGeneralLoadSuccess {
  final Drive drive;

  FsEntryDriveLoadSuccess({
    String name,
    DateTime lastUpdated,
    DateTime dateCreated,
    this.drive,
  }) : super(name: name, lastUpdated: lastUpdated, dateCreated: dateCreated);

  @override
  List<Object> get props => [name, lastUpdated, dateCreated, drive];
}

class FsEntryFolderLoadSuccess extends FsEntryGeneralLoadSuccess {
  final FolderEntry folder;

  FsEntryFolderLoadSuccess(
      {String name, DateTime lastUpdated, DateTime dateCreated, this.folder})
      : super(name: name, lastUpdated: lastUpdated, dateCreated: dateCreated);

  @override
  List<Object> get props => [name, lastUpdated, dateCreated, folder];
}

class FsEntryFileLoadSuccess extends FsEntryGeneralLoadSuccess {
  final FileEntry file;

  FsEntryFileLoadSuccess(
      {String name, DateTime lastUpdated, DateTime dateCreated, this.file})
      : super(name: name, lastUpdated: lastUpdated, dateCreated: dateCreated);

  @override
  List<Object> get props => [name, lastUpdated, dateCreated, file];
}

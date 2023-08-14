part of 'fs_entry_info_cubit.dart';

abstract class FsEntryInfoState extends Equatable {
  const FsEntryInfoState();

  @override
  List<Object> get props => [];
}

class FsEntryInfoInitial extends FsEntryInfoState {}

class FsEntryInfoSuccess<T> extends FsEntryInfoState {
  final String name;
  final DateTime lastUpdated;
  final DateTime dateCreated;
  final T entry;
  final String metadataTxId;

  const FsEntryInfoSuccess({
    required this.name,
    required this.lastUpdated,
    required this.dateCreated,
    required this.entry,
    required this.metadataTxId,
  });

  @override
  List<Object> get props => [name, lastUpdated, dateCreated];
}

class FsEntryDriveInfoSuccess extends FsEntryInfoSuccess<Drive> {
  @override
  final String name;
  @override
  final DateTime lastUpdated;
  @override
  final DateTime dateCreated;

  final Drive drive;
  final FolderRevision rootFolderRevision;
  final FolderNode rootFolderTree;

  const FsEntryDriveInfoSuccess({
    required this.name,
    required this.lastUpdated,
    required this.dateCreated,
    required this.drive,
    required this.rootFolderRevision,
    required this.rootFolderTree,
    required String metadataTxId,
  }) : super(
          name: name,
          lastUpdated: lastUpdated,
          dateCreated: dateCreated,
          entry: drive,
          metadataTxId: metadataTxId,
        );

  @override
  List<Object> get props => [
        name,
        lastUpdated,
        dateCreated,
        rootFolderRevision,
        rootFolderTree,
      ];
}

class FsEntryInfoFailure extends FsEntryInfoState {}

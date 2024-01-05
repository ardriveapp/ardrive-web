part of 'fs_entry_info_cubit.dart';

abstract class FsEntryInfoState extends Equatable {
  const FsEntryInfoState();

  @override
  List<Object?> get props => [];
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
  List<Object?> get props => [name, lastUpdated, dateCreated];
}

class FsEntryFileInfoSuccess extends FsEntryInfoSuccess<FileEntry> {
  final LicenseMeta? licenseMeta;
  final LicenseParams? licenseParams;

  const FsEntryFileInfoSuccess({
    required super.name,
    required super.lastUpdated,
    required super.dateCreated,
    required super.entry,
    required super.metadataTxId,
    required this.licenseMeta,
    required this.licenseParams,
  });

  @override
  List<Object?> get props => [name, lastUpdated, dateCreated, licenseMeta];
}

class FsEntryDriveInfoSuccess extends FsEntryInfoSuccess<Drive> {
  final Drive drive;
  final FolderRevision rootFolderRevision;
  final FolderNode rootFolderTree;

  const FsEntryDriveInfoSuccess({
    required super.name,
    required super.lastUpdated,
    required super.dateCreated,
    required this.drive,
    required this.rootFolderRevision,
    required this.rootFolderTree,
    required String metadataTxId,
  }) : super(
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

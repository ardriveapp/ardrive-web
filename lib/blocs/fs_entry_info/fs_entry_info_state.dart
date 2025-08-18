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

class FsEntryFileInfoSuccess extends FsEntryInfoSuccess<void> {
  final LicenseState? licenseState;
  final String? ownerAddress;

  const FsEntryFileInfoSuccess({
    required super.name,
    required super.lastUpdated,
    required super.dateCreated,
    required super.metadataTxId,
    required this.licenseState,
    this.ownerAddress,
  }) : super(
          entry: null,
        );

  @override
  List<Object?> get props => [name, lastUpdated, dateCreated, licenseState, ownerAddress];
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
    required super.metadataTxId,
  }) : super(
          entry: drive,
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

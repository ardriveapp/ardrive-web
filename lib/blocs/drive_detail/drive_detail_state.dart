part of 'drive_detail_cubit.dart';

@immutable
abstract class DriveDetailState extends Equatable {
  @override
  List<Object?> get props => [];
}

class DriveDetailLoadInProgress extends DriveDetailState {}

class DriveDetailLoadSuccess extends DriveDetailState {
  final Drive currentDrive;
  final bool hasWritePermissions;
  final bool driveIsEmpty;
  final bool multiselect;
  final bool hasFoldersSelected;
  final int? selectedPage;

  final FolderWithContents folderInView;

  final List<BreadCrumbRowInfo> pathSegments;

  final DriveOrder contentOrderBy;
  final OrderingMode contentOrderingMode;

  final List<SelectedItem> selectedItems;
  final bool showSelectedItemDetails;

  /// The preview URL for the selected file.
  ///
  /// Null if no file is selected.
  final String? selectedFilePreviewUrl;
  final ArDriveDataTableItem? selectedItem;

  final int rowsPerPage;
  final List<int> availableRowsPerPage;
  final int _equatableBust = DateTime.now().millisecondsSinceEpoch;

  final List<ArDriveDataTableItem> currentFolderContents;

  final Map<int, bool> columnVisibility;
  final Key? forceRebuildKey;

  DriveDetailLoadSuccess({
    required this.currentDrive,
    required this.hasWritePermissions,
    required this.folderInView,
    required this.contentOrderBy,
    required this.contentOrderingMode,
    required this.rowsPerPage,
    required this.availableRowsPerPage,
    required this.multiselect,
    this.selectedItems = const [],
    this.showSelectedItemDetails = false,
    this.hasFoldersSelected = false,
    this.selectedFilePreviewUrl,
    required this.driveIsEmpty,
    required this.selectedItem,
    required this.currentFolderContents,
    required this.columnVisibility,
    this.forceRebuildKey,
    required this.pathSegments,
    this.selectedPage,
  });

  DriveDetailLoadSuccess copyWith({
    Drive? currentDrive,
    bool? hasWritePermissions,
    FolderWithContents? folderInView,
    DriveOrder? contentOrderBy,
    OrderingMode? contentOrderingMode,
    List<SelectedItem>? selectedItems,
    bool? showSelectedItemDetails,
    String? selectedFilePreviewUrl,
    int? rowsPerPage,
    List<int>? availableRowsPerPage,
    bool? driveIsEmpty,
    bool? multiselect,
    bool? hasFoldersSelected,
    ArDriveDataTableItem? selectedItem,
    List<ArDriveDataTableItem>? currentFolderContents,
    Key? forceRebuildKey,
    List<BreadCrumbRowInfo>? pathSegments,
    int? selectedPage,
  }) =>
      DriveDetailLoadSuccess(
        selectedPage: selectedPage ?? this.selectedPage,
        columnVisibility: columnVisibility,
        forceRebuildKey: forceRebuildKey ?? this.forceRebuildKey,
        selectedItem: selectedItem ?? this.selectedItem,
        hasFoldersSelected: hasFoldersSelected ?? this.hasFoldersSelected,
        currentDrive: currentDrive ?? this.currentDrive,
        multiselect: multiselect ?? this.multiselect,
        hasWritePermissions: hasWritePermissions ?? this.hasWritePermissions,
        folderInView: folderInView ?? this.folderInView,
        contentOrderBy: contentOrderBy ?? this.contentOrderBy,
        contentOrderingMode: contentOrderingMode ?? this.contentOrderingMode,
        selectedItems: selectedItems ?? this.selectedItems,
        showSelectedItemDetails:
            showSelectedItemDetails ?? this.showSelectedItemDetails,
        selectedFilePreviewUrl:
            selectedFilePreviewUrl ?? this.selectedFilePreviewUrl,
        availableRowsPerPage: availableRowsPerPage ?? this.availableRowsPerPage,
        rowsPerPage: rowsPerPage ?? this.rowsPerPage,
        driveIsEmpty: driveIsEmpty ?? this.driveIsEmpty,
        currentFolderContents:
            currentFolderContents ?? this.currentFolderContents,
        pathSegments: pathSegments ?? this.pathSegments,
      );

  @override
  List<Object?> get props => [
        currentDrive,
        hasWritePermissions,
        folderInView,
        currentFolderContents,
        contentOrderBy,
        contentOrderingMode,
        showSelectedItemDetails,
        selectedFilePreviewUrl,
        rowsPerPage,
        availableRowsPerPage,
        selectedItems,
        _equatableBust,
        driveIsEmpty,
        multiselect,
        forceRebuildKey,
        selectedItem,
        selectedPage,
      ];
  SelectedItem? maybeSelectedItem() =>
      selectedItems.isNotEmpty ? selectedItems.first : null;
  bool isViewingRootFolder() =>
      folderInView.folder.id != currentDrive.rootFolderId;
}

/// [DriveDetailLoadNotFound] means that the specified drive could not be found attached to
/// the user's profile.
class DriveDetailLoadNotFound extends DriveDetailState {}

/// [DriveDetailLoadUnsynced] means the drive's metadata exists but its content
/// is not (yet) locally available to open.
///
/// Two ways in: the drive has never been synced (`lastBlockHeight` 0 or null),
/// or it synced but its root folder row is missing, so the explorer has no
/// folder to mount. Both are recoverable and both are re-checked by
/// `DriveDetailCubit._onSyncCompleted`, which opens the drive once the content
/// lands.
class DriveDetailLoadUnsynced extends DriveDetailState {
  final Drive drive;
  final bool showDriveInfo;
  final ArDriveDataTableItem? selectedItem;

  /// Whether a sync has already been run against this drive and came back with
  /// nothing.
  ///
  /// Without it the card the user pressed Sync Now on is re-rendered exactly
  /// as it was, which reads as a button that did nothing - when what actually
  /// happened is that the sync ran, finished, and found no root metadata on
  /// chain to open. The card says that instead, so the user is not sent round
  /// the same loop expecting a different answer.
  final bool syncFoundNothing;

  DriveDetailLoadUnsynced({
    required this.drive,
    this.showDriveInfo = false,
    this.selectedItem,
    this.syncFoundNothing = false,
  });

  DriveDetailLoadUnsynced copyWith({
    Drive? drive,
    bool? showDriveInfo,
    Object? selectedItem = _driveDetailAbsent,
    bool? syncFoundNothing,
  }) {
    return DriveDetailLoadUnsynced(
      drive: drive ?? this.drive,
      showDriveInfo: showDriveInfo ?? this.showDriveInfo,
      syncFoundNothing: syncFoundNothing ?? this.syncFoundNothing,
      selectedItem: identical(selectedItem, _driveDetailAbsent)
          ? this.selectedItem
          : selectedItem as ArDriveDataTableItem?,
    );
  }

  @override
  List<Object?> get props =>
      [drive, showDriveInfo, selectedItem, syncFoundNothing];
}

/// The user genuinely has no drives - we looked, and there were none.
///
/// Only ever emitted after the drive list has actually been refreshed. It is
/// the "Getting Started" screen, and getting here off an empty local database
/// that nobody has filled in yet tells a user with drives that they have none.
class DriveDetailLoadEmpty extends DriveDetailState {}

/// The drive list could not be read at all.
///
/// The third thing an empty database can mean, and the one the app used to
/// render as the second: we asked, and could not find out. It is not
/// [DriveDetailLoadEmpty] - the user is not told they have no drives, and is
/// not offered a drive to create - and it is not
/// [DriveDetailLoadInProgress], because nothing is still running.
class DriveDetailDrivesUnavailable extends DriveDetailState {}

class DriveInitialLoading extends DriveDetailState {}

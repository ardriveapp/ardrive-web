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

  final FolderWithContents folderInView;

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
    this.selectedItem,
    required this.currentFolderContents,
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
  }) =>
      DriveDetailLoadSuccess(
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
      );

  @override
  List<Object?> get props => [
        currentDrive,
        hasWritePermissions,
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
      ];
  SelectedItem? maybeSelectedItem() =>
      selectedItems.isNotEmpty ? selectedItems.first : null;
  bool isViewingRootFolder() =>
      folderInView.folder.id != currentDrive.rootFolderId;
}

/// [DriveDetailLoadNotFound] means that the specified drive could not be found attached to
/// the user's profile.
class DriveDetailLoadNotFound extends DriveDetailState {}

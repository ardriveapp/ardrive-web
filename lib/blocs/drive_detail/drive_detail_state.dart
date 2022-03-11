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

  final FolderWithContents folderInView;

  final DriveOrder contentOrderBy;
  final OrderingMode contentOrderingMode;

  final SelectedItem? maybeSelectedItem;
  final bool showSelectedItemDetails;

  /// The preview URL for the selected file.
  ///
  /// Null if no file is selected.
  final Uri? selectedFilePreviewUrl;

  final int rowsPerPage;
  final List<int> availableRowsPerPage;
  final int _equatableBust = DateTime.now().millisecondsSinceEpoch;

  DriveDetailLoadSuccess({
    required this.currentDrive,
    required this.hasWritePermissions,
    required this.folderInView,
    required this.contentOrderBy,
    required this.contentOrderingMode,
    required this.rowsPerPage,
    required this.availableRowsPerPage,
    this.maybeSelectedItem,
    this.showSelectedItemDetails = false,
    this.selectedFilePreviewUrl,
  });

  DriveDetailLoadSuccess copyWith({
    Drive? currentDrive,
    bool? hasWritePermissions,
    FolderWithContents? folderInView,
    DriveOrder? contentOrderBy,
    OrderingMode? contentOrderingMode,
    SelectedItem? maybeSelectedItem,
    bool? showSelectedItemDetails,
    Uri? selectedFilePreviewUrl,
    int? rowsPerPage,
    List<int>? availableRowsPerPage,
  }) =>
      DriveDetailLoadSuccess(
        currentDrive: currentDrive ?? this.currentDrive,
        hasWritePermissions: hasWritePermissions ?? this.hasWritePermissions,
        folderInView: folderInView ?? this.folderInView,
        contentOrderBy: contentOrderBy ?? this.contentOrderBy,
        contentOrderingMode: contentOrderingMode ?? this.contentOrderingMode,
        maybeSelectedItem: maybeSelectedItem ?? this.maybeSelectedItem,
        showSelectedItemDetails:
            showSelectedItemDetails ?? this.showSelectedItemDetails,
        selectedFilePreviewUrl:
            selectedFilePreviewUrl ?? this.selectedFilePreviewUrl,
        availableRowsPerPage: availableRowsPerPage ?? this.availableRowsPerPage,
        rowsPerPage: rowsPerPage ?? this.rowsPerPage,
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
        maybeSelectedItem,
        _equatableBust,
      ];

  bool isViewingRootFolder() =>
      folderInView.folder.id != currentDrive.rootFolderId;
}

/// [DriveDetailLoadNotFound] means that the specified drive could not be found attached to
/// the user's profile.
class DriveDetailLoadNotFound extends DriveDetailState {}

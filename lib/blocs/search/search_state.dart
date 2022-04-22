part of 'search_cubit.dart';

@immutable
abstract class SearchState extends Equatable {
  @override
  List<Object?> get props => [];
}

class SearchLoadInProgress extends SearchState {}

class SearchLoadSuccess extends SearchState {
  final Drive currentDrive;
  final bool hasWritePermissions;
  final bool driveIsEmpty;

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

  SearchLoadSuccess({
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
    required this.driveIsEmpty,
  });

  SearchLoadSuccess copyWith({
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
    bool? driveIsEmpty,
  }) =>
      SearchLoadSuccess(
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
        driveIsEmpty: driveIsEmpty ?? this.driveIsEmpty,
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
        driveIsEmpty,
      ];

  bool isViewingRootFolder() =>
      folderInView.folder.id != currentDrive.rootFolderId;
}

/// [SearchLoadNotFound] means that the specified drive could not be found attached to
/// the user's profile.
class SearchLoadNotFound extends SearchState {}

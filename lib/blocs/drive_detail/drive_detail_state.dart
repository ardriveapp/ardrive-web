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

  final FolderWithContents currentFolder;

  final DriveOrder contentOrderBy;
  final OrderingMode contentOrderingMode;

  final String? selectedItemId;
  final bool selectedItemIsFolder;
  final bool selectedItemIsGhost;
  final bool showSelectedItemDetails;

  /// The preview URL for the selected file.
  ///
  /// Null if no file is selected.
  final Uri? selectedFilePreviewUrl;

  final int rowsPerPage;
  final List<int> availableRowsPerPage;

  DriveDetailLoadSuccess({
    required this.currentDrive,
    required this.hasWritePermissions,
    required this.currentFolder,
    required this.contentOrderBy,
    required this.contentOrderingMode,
    required this.rowsPerPage,
    required this.availableRowsPerPage,
    this.selectedItemId,
    this.selectedItemIsFolder = false,
    this.selectedItemIsGhost = false,
    this.showSelectedItemDetails = false,
    this.selectedFilePreviewUrl,
  });

  DriveDetailLoadSuccess copyWith({
    Drive? currentDrive,
    bool? hasWritePermissions,
    FolderWithContents? currentFolder,
    DriveOrder? contentOrderBy,
    OrderingMode? contentOrderingMode,
    String? selectedItemId,
    bool? selectedItemIsFolder,
    bool? selectedItemIsGhost,
    bool? showSelectedItemDetails,
    Uri? selectedFilePreviewUrl,
    int? rowsPerPage,
    List<int>? availableRowsPerPage,
  }) =>
      DriveDetailLoadSuccess(
        currentDrive: currentDrive ?? this.currentDrive,
        hasWritePermissions: hasWritePermissions ?? this.hasWritePermissions,
        currentFolder: currentFolder ?? this.currentFolder,
        contentOrderBy: contentOrderBy ?? this.contentOrderBy,
        contentOrderingMode: contentOrderingMode ?? this.contentOrderingMode,
        selectedItemId: selectedItemId ?? this.selectedItemId,
        selectedItemIsFolder: selectedItemIsFolder ?? this.selectedItemIsFolder,
        selectedItemIsGhost: selectedItemIsGhost ?? this.selectedItemIsGhost,
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
        currentFolder,
        contentOrderBy,
        contentOrderingMode,
        selectedItemId,
        selectedItemIsFolder,
        selectedItemIsGhost,
        showSelectedItemDetails,
        selectedFilePreviewUrl,
        rowsPerPage,
        availableRowsPerPage
      ];
}

/// [DriveDetailLoadNotFound] means that the specified drive could not be found attached to
/// the user's profile.
class DriveDetailLoadNotFound extends DriveDetailState {}

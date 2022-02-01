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

  final String? selectedItemId;
  final bool selectedItemIsFolder;
  final bool selectedItemIsGhost;
  final bool showSelectedItemDetails;

  /// The preview URL for the selected file.
  ///
  /// Null if no file is selected.
  final Uri? selectedFilePreviewUrl;

  DriveDetailLoadSuccess({
    required this.currentDrive,
    required this.hasWritePermissions,
    required this.folderInView,
    required this.contentOrderBy,
    required this.contentOrderingMode,
    this.selectedItemId,
    this.selectedItemIsFolder = false,
    this.selectedItemIsGhost = false,
    this.showSelectedItemDetails = false,
    this.selectedFilePreviewUrl,
  });

  DriveDetailLoadSuccess copyWith({
    Drive? currentDrive,
    bool? hasWritePermissions,
    FolderWithContents? folderInView,
    DriveOrder? contentOrderBy,
    OrderingMode? contentOrderingMode,
    String? selectedItemId,
    bool? selectedItemIsFolder,
    bool? selectedItemIsGhost,
    bool? showSelectedItemDetails,
    Uri? selectedFilePreviewUrl,
  }) =>
      DriveDetailLoadSuccess(
        currentDrive: currentDrive ?? this.currentDrive,
        hasWritePermissions: hasWritePermissions ?? this.hasWritePermissions,
        folderInView: folderInView ?? this.folderInView,
        contentOrderBy: contentOrderBy ?? this.contentOrderBy,
        contentOrderingMode: contentOrderingMode ?? this.contentOrderingMode,
        selectedItemId: selectedItemId ?? this.selectedItemId,
        selectedItemIsFolder: selectedItemIsFolder ?? this.selectedItemIsFolder,
        selectedItemIsGhost: selectedItemIsGhost ?? this.selectedItemIsGhost,
        showSelectedItemDetails:
            showSelectedItemDetails ?? this.showSelectedItemDetails,
        selectedFilePreviewUrl:
            selectedFilePreviewUrl ?? this.selectedFilePreviewUrl,
      );

  @override
  List<Object?> get props => [
        currentDrive,
        hasWritePermissions,
        contentOrderBy,
        contentOrderingMode,
        selectedItemId,
        selectedItemIsFolder,
        selectedItemIsGhost,
        showSelectedItemDetails,
        selectedFilePreviewUrl,
      ];

  FolderID? getSelectedFolderId() {
    if (selectedItemIsFolder) {
      return selectedItemId;
    } else if (folderInView.folder!.id != currentDrive.rootFolderId) {
      // If nothing is selected and we are in a subfolder
      // Show the info of that subfolder
      return folderInView.folder!.id;
    }
    return null;
  }

  FileID? getSelectedFileId() => !selectedItemIsFolder ? selectedItemId : null;
}

/// [DriveDetailLoadNotFound] means that the specified drive could not be found attached to
/// the user's profile.
class DriveDetailLoadNotFound extends DriveDetailState {}

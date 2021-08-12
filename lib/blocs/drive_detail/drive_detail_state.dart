part of 'drive_detail_cubit.dart';

@immutable
abstract class DriveDetailState extends Equatable {
  @override
  List<Object?> get props => [];
}

class DriveDetailLoadInProgress extends DriveDetailState {}

class DriveDetailLoadSuccess extends DriveDetailState {
  final Drive? currentDrive;
  final bool? hasWritePermissions;

  final FolderWithContents? currentFolder;

  final DriveOrder? contentOrderBy;
  final OrderingMode? contentOrderingMode;

  final String? selectedItemId;
  final bool selectedItemIsFolder;
  final bool showSelectedItemDetails;

  /// The preview URL for the selected file.
  ///
  /// Null if no file is selected.
  final Uri? selectedFilePreviewUrl;

  DriveDetailLoadSuccess({
    this.currentDrive,
    this.hasWritePermissions,
    this.currentFolder,
    this.contentOrderBy,
    this.contentOrderingMode,
    this.selectedItemId,
    this.selectedItemIsFolder = false,
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
    bool? showSelectedItemDetails,
    Uri? selectedFilePreviewUrl,
  }) =>
      DriveDetailLoadSuccess(
        currentDrive: currentDrive ?? this.currentDrive,
        hasWritePermissions: hasWritePermissions ?? this.hasWritePermissions,
        currentFolder: currentFolder ?? this.currentFolder,
        contentOrderBy: contentOrderBy ?? this.contentOrderBy,
        contentOrderingMode: contentOrderingMode ?? this.contentOrderingMode,
        selectedItemId: selectedItemId ?? this.selectedItemId,
        selectedItemIsFolder: selectedItemIsFolder ?? this.selectedItemIsFolder,
        showSelectedItemDetails:
            showSelectedItemDetails ?? this.showSelectedItemDetails,
        selectedFilePreviewUrl:
            selectedFilePreviewUrl ?? this.selectedFilePreviewUrl,
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
        showSelectedItemDetails,
        selectedFilePreviewUrl,
      ];
}

/// [DriveDetailLoadNotFound] means that the specified drive could not be found attached to
/// the user's profile.
class DriveDetailLoadNotFound extends DriveDetailState {}

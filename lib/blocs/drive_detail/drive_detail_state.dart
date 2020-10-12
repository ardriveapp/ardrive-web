part of 'drive_detail_cubit.dart';

@immutable
abstract class DriveDetailState extends Equatable {
  @override
  List<Object> get props => [];
}

class FolderLoadInProgress extends DriveDetailState {}

class FolderLoadSuccess extends DriveDetailState {
  final Drive currentDrive;
  final bool hasWritePermissions;

  final FolderWithContents currentFolder;

  final String selectedItemId;
  final bool selectedItemIsFolder;
  final bool showSelectedItemDetails;

  FolderLoadSuccess({
    this.currentDrive,
    this.hasWritePermissions,
    this.currentFolder,
    this.selectedItemId,
    this.selectedItemIsFolder = false,
    this.showSelectedItemDetails = false,
  });

  FolderLoadSuccess copyWith({
    Drive currentDrive,
    bool hasWritePermissions,
    FolderWithContents currentFolder,
    String selectedItemId,
    bool selectedItemIsFolder,
    bool showSelectedItemDetails,
  }) =>
      FolderLoadSuccess(
        currentDrive: currentDrive ?? this.currentDrive,
        hasWritePermissions: hasWritePermissions ?? this.hasWritePermissions,
        currentFolder: currentFolder ?? this.currentFolder,
        selectedItemId: selectedItemId ?? this.selectedItemId,
        selectedItemIsFolder: selectedItemIsFolder ?? this.selectedItemIsFolder,
        showSelectedItemDetails:
            showSelectedItemDetails ?? this.showSelectedItemDetails,
      );

  @override
  List<Object> get props => [
        currentDrive,
        hasWritePermissions,
        currentFolder,
        selectedItemId,
        selectedItemIsFolder,
        showSelectedItemDetails,
      ];
}

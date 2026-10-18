import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/search/search_result.dart';

/// Goes to a search result: its drive, its folder, or the folder a file is in
/// with the file picked out.
///
/// One way to go there for every place results are listed, the dropdown and
/// the full results alike. It never closes anything itself: the caller closes
/// its own dialog or dropdown first. Holding the cubits rather than a
/// `BuildContext` is deliberate too: the search box that asked is often
/// rebuilt mid-way, when selecting a drive changes the page under it.
class SearchResultNavigator {
  const SearchResultNavigator({
    required this.drivesCubit,
    required this.driveDetailCubit,
    this.onNavigateToFolder,
  });

  final DrivesCubit drivesCubit;
  final DriveDetailCubit driveDetailCubit;

  /// How to reach a folder, when calling `openFolder` on [driveDetailCubit]
  /// will not get there.
  ///
  /// The explorer's cubit is long-lived and switches drives underneath the
  /// page, so it can simply be told to open a folder in another drive. The
  /// drives list's is not: selecting a drive there replaces the whole subtree,
  /// and the cubit this was handed is torn down mid-navigation - leaving the
  /// reader at the drive root rather than the file they searched for. Callers
  /// in that position pass this and the navigation goes through the router
  /// instead.
  final void Function(String driveId, String folderId, {String? itemId})?
      onNavigateToFolder;

  Future<void> open(SearchResult searchResult) async {
    final result = searchResult.result;

    if (result is FileEntry) {
      await _openFile(result);
    } else if (result is FolderEntry) {
      final otherDriveId = (searchResult.parentFolder == null)
          ? searchResult.drive.id
          : searchResult.parentFolder!.driveId;

      final navigate = onNavigateToFolder;

      if (navigate != null) {
        // Asked for before the selection, because the selection is what
        // carries it - see [onNavigateToFolder].
        navigate(otherDriveId, result.id);
        drivesCubit.selectDrive(searchResult.drive.id);

        return;
      }

      drivesCubit.selectDrive(searchResult.drive.id);

      driveDetailCubit.openFolder(
        otherDriveId: otherDriveId,
        folderId: result.id,
      );
    } else if (result is Drive) {
      drivesCubit.selectDrive(result.id);
    }
  }

  Future<void> _openFile(FileEntry file) async {
    final navigate = onNavigateToFolder;

    if (navigate != null) {
      // The folder the file is in, and the file to pick out of it once it
      // opens - the same thing the explorer's path below does with
      // `selectedItemId`, taking the long way round because the cubit that
      // could be told directly is about to be torn down.
      navigate(file.driveId, file.parentFolderId, itemId: file.id);
      drivesCubit.selectDrive(file.driveId);

      return;
    }

    await Future.delayed(const Duration(milliseconds: 100));

    drivesCubit.selectDrive(file.driveId);

    await Future.delayed(const Duration(milliseconds: 100));

    driveDetailCubit.openFolder(
      otherDriveId: file.driveId,
      folderId: file.parentFolderId,
      selectedItemId: file.id,
    );
  }
}

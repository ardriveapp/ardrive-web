import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/utils/logger.dart';

class BreadcrumbBuilder {
  final FolderRepository _folderRepository;

  BreadcrumbBuilder(this._folderRepository);

  Future<List<BreadCrumbRowInfo>> buildForFolder({
    required String folderId,
    required String rootFolderId,
    required String driveId,
  }) async {
    List<BreadCrumbRowInfo> breadcrumbs = [];
    String? currentFolderId = folderId;

    while (currentFolderId != null && currentFolderId != rootFolderId) {
      final folderRevision = await _folderRepository
          .getLatestFolderRevisionInfo(driveId, currentFolderId);
      if (folderRevision == null) {
        logger.e('FolderRevision not found for folderId: $currentFolderId');
        throw Exception(
            'FolderRevision not found for folderId: $currentFolderId');
      }

      breadcrumbs.insert(
        0,
        BreadCrumbRowInfo(
          text: folderRevision.name,
          targetId: folderRevision.folderId,
        ),
      );
      currentFolderId = folderRevision.parentFolderId;
    }

    return breadcrumbs;
  }
}

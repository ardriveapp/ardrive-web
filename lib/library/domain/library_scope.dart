import 'package:ardrive/library/domain/library_config.dart';
import 'package:ardrive/models/models.dart';

/// Whether [folderId] is a place the library shows: a folder of its drive,
/// not hidden and not inside a hidden folder, and, for a folder library, that
/// folder or one beneath it.
///
/// A link into a library names a folder by id, and the page will open
/// whatever the database holds under that id. The snapshot holds the whole
/// drive, so without this a folder library's link could be edited to open
/// any other folder of the drive, which its owner did not publish.
///
/// Walks up through parents, which ArFS does not promise are acyclic: a
/// broken or hostile snapshot could make a loop, so the walk is bounded.
Future<bool> isInLibraryScope({
  required DriveDao driveDao,
  required LibraryConfig config,
  required String folderId,
}) async {
  final scopeRoot = config.scopeRootFolderId;
  String? current = folderId;
  for (var depth = 0; current != null && depth < _maxDepth; depth++) {
    final folder =
        await driveDao.folderById(folderId: current).getSingleOrNull();
    if (folder == null || folder.driveId != config.driveId) return false;
    // The folder the owner published is shown whatever its flag says.
    if (folder.id == scopeRoot) return true;
    // Below it, a library never shows a hidden folder, or anything inside one.
    if (folder.isHidden) return false;
    if (folder.id == config.rootFolderId) return false;
    current = folder.parentFolderId;
  }
  return false;
}

/// Deeper than any real drive; past it the walk stops and answers no.
const _maxDepth = 256;

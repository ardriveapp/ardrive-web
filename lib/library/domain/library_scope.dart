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

/// Which folders of a library's drive it shows, decided in memory from one
/// read of the drive's folders: for counting a library and searching it,
/// which ask about many folders at once, where [isInLibraryScope] asks the
/// database about one. A library's database does not change once it is
/// open, so this can be read once and kept.
///
/// Answers as [isInLibraryScope] does, and also leaves out ghost folders
/// (folders known only from the files inside them), which the explorer does
/// not list either.
class LibraryFolders {
  LibraryFolders._(this._config, this._byId);

  static Future<LibraryFolders> load(
    DriveDao driveDao,
    LibraryConfig config,
  ) async {
    final db = driveDao.attachedDatabase;
    final folders = await (db.select(db.folderEntries)
          ..where((f) => f.driveId.equals(config.driveId)))
        .get();
    return LibraryFolders._(config, {for (final f in folders) f.id: f});
  }

  final LibraryConfig _config;
  final Map<String, FolderEntry> _byId;
  final _shown = <String, bool>{};

  /// Whether the library shows the folder [folderId] (and so can list what is
  /// in it).
  bool shows(String folderId) {
    final known = _shown[folderId];
    if (known != null) return known;
    // Walk up, remembering the path, so each folder is decided once.
    final path = <String>[];
    String? current = folderId;
    var answer = false;
    while (current != null && path.length < _maxDepth) {
      final cached = _shown[current];
      if (cached != null) {
        answer = cached;
        break;
      }
      final folder = _byId[current];
      if (folder == null) break;
      path.add(current);
      if (folder.id == _config.scopeRootFolderId) {
        answer = true;
        break;
      }
      if (folder.isHidden || folder.isGhost) break;
      if (folder.id == _config.rootFolderId) break;
      current = folder.parentFolderId;
    }
    for (final id in path) {
      _shown[id] = answer;
    }
    return answer;
  }

  /// Whether the library lists a file that is in [parentFolderId].
  bool showsFile({required bool isHidden, required String parentFolderId}) =>
      !isHidden && shows(parentFolderId);
}

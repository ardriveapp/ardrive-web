import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/models/models.dart';

/// Whether [folderId] is a place the publication shows: a folder of its drive,
/// not hidden and not inside a hidden folder, and, for a folder publication, that
/// folder or one beneath it.
///
/// A link into a publication names a folder by id, and the page will open
/// whatever the database holds under that id. The snapshot holds the whole
/// drive, so without this a folder publication's link could be edited to open
/// any other folder of the drive, which its owner did not publish.
///
/// Walks up through parents, which ArFS does not promise are acyclic: a
/// broken or hostile snapshot could make a loop, so the walk is bounded.
Future<bool> isInPublicationScope({
  required DriveDao driveDao,
  required PublicationConfig config,
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
    // Below it, a publication never shows a hidden folder, or anything inside one,
    // nor a ghost folder, which the explorer does not list.
    if (folder.isHidden || folder.isGhost) return false;
    if (folder.id == config.rootFolderId) return false;
    current = folder.parentFolderId;
  }
  return false;
}

/// Deeper than any real drive; past it the walk stops and answers no.
const _maxDepth = 256;

/// What a publication shows, decided in memory from one read of its drive's
/// folders and one of its files: for counting a publication and searching it,
/// which ask about many items at once, where [isInPublicationScope] asks the
/// database about one folder. A publication's database does not change once it
/// is open, so this can be read once and kept.
///
/// Folders as [isInPublicationScope] decides them, less ghost folders (known only
/// from the files inside them). Files that are not hidden, in a folder it
/// shows, and whose latest revision is neither failed nor pending. That is
/// what the explorer lists, which reads files through the same query.
class PublicationContents {
  PublicationContents._(this._config, this._folders, this._files);

  /// The open publication's contents, set when it is ready; null before, and on
  /// every page that is not a publication. For code that reads a folder's
  /// whole tree from the database (downloads, the info panel), which would
  /// otherwise see the drive behind the publication: it prunes with [prune], and
  /// in publication mode refuses outright while this is null.
  static PublicationContents? open;

  static Future<PublicationContents> load(
    DriveDao driveDao,
    PublicationConfig config,
  ) async {
    final db = driveDao.attachedDatabase;
    final folders = await (db.select(db.folderEntries)
          ..where((f) => f.driveId.equals(config.driveId)))
        .get();
    final files = await driveDao
        .filesInDriveWithRevisionTransactions(driveId: config.driveId)
        .get();
    return PublicationContents._(
      config,
      {for (final f in folders) f.id: f},
      {for (final f in files) f.id: f},
    );
  }

  final PublicationConfig _config;

  PublicationConfig get config => _config;

  final Map<String, FolderEntry> _folders;
  final Map<String, FileWithLatestRevisionTransactions> _files;
  final _shown = <String, bool>{};

  /// Whether the publication shows the folder [folderId] (and so can list what is
  /// in it).
  bool showsFolder(String folderId) {
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
      final folder = _folders[current];
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

  /// Whether the publication lists the file [fileId].
  bool showsFile(String fileId) {
    final file = _files[fileId];
    return file != null && _isListed(file);
  }

  /// Every file the publication lists.
  Iterable<FileWithLatestRevisionTransactions> get files =>
      _files.values.where(_isListed);

  /// [node] with only what the publication lists: its subfolders and files that
  /// the publication shows, all the way down. Null if it does not show [node]
  /// itself.
  FolderNode? prune(FolderNode node) {
    if (!showsFolder(node.folder.id)) return null;
    return FolderNode(
      folder: node.folder,
      subfolders: [
        for (final subfolder in node.subfolders)
          if (prune(subfolder) case final shown?) shown,
      ],
      files: {
        for (final entry in node.files.entries)
          if (showsFile(entry.key)) entry.key: entry.value,
      },
    );
  }

  bool _isListed(FileWithLatestRevisionTransactions file) {
    if (file.isHidden || !showsFolder(file.parentFolderId)) return false;
    final status = fileStatusFromTransactions(file.metadataTx, file.dataTx);
    return status != TransactionStatus.failed &&
        status != TransactionStatus.pending;
  }
}

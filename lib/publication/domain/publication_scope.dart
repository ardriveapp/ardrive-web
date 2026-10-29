import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/models/models.dart';
import 'package:equatable/equatable.dart';

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
  PublicationContents._(
    this._config,
    this._rootFolderId,
    this._scopeRootFolderId,
    this._folders,
    this._files,
  );

  /// The open publication's contents, set when it is ready; null before, and on
  /// every page that is not a publication. For code that reads a folder's
  /// whole tree from the database (downloads, the info panel), which would
  /// otherwise see the drive behind the publication: it prunes with [prune], and
  /// in publication mode refuses outright while this is null.
  static PublicationContents? open;

  static Future<PublicationContents> load(
    DriveDao driveDao,
    PublicationConfig config,
  ) =>
      _load(
        driveDao,
        config: config,
        driveId: config.driveId,
        rootFolderId: config.rootFolderId,
        scopeRootFolderId: config.scopeRootFolderId,
      );

  /// What a publication of [scopeRootFolderId] would show: the publish
  /// dialog asks before any `publication.json` exists.
  static Future<PublicationContents> loadScope(
    DriveDao driveDao, {
    required String driveId,
    required String rootFolderId,
    required String scopeRootFolderId,
  }) =>
      _load(
        driveDao,
        driveId: driveId,
        rootFolderId: rootFolderId,
        scopeRootFolderId: scopeRootFolderId,
      );

  static Future<PublicationContents> _load(
    DriveDao driveDao, {
    PublicationConfig? config,
    required String driveId,
    required String rootFolderId,
    required String scopeRootFolderId,
  }) async {
    final db = driveDao.attachedDatabase;
    final folders = await (db.select(db.folderEntries)
          ..where((f) => f.driveId.equals(driveId)))
        .get();
    final files = await driveDao
        .filesInDriveWithRevisionTransactions(driveId: driveId)
        .get();
    return PublicationContents._(
      config,
      rootFolderId,
      scopeRootFolderId,
      {for (final f in folders) f.id: f},
      {for (final f in files) f.id: f},
    );
  }

  final PublicationConfig? _config;

  /// The open publication's settings. Only for contents loaded with [load].
  PublicationConfig get config => _config!;

  final String _rootFolderId;
  final String _scopeRootFolderId;

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
      if (folder.id == _scopeRootFolderId) {
        answer = true;
        break;
      }
      if (folder.isHidden || folder.isGhost) break;
      if (folder.id == _rootFolderId) break;
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

  /// The files [summarize] counts as pending: in a folder the publication
  /// shows, not hidden, with a latest upload not confirmed yet.
  Iterable<String> get pendingFileIds => _files.values
      .where((file) =>
          !file.isHidden &&
          showsFolder(file.parentFolderId) &&
          fileStatusFromTransactions(file.metadataTx, file.dataTx) ==
              TransactionStatus.pending)
      .map((file) => file.id);

  bool _isListed(FileWithLatestRevisionTransactions file) {
    if (file.isHidden || !showsFolder(file.parentFolderId)) return false;
    final status = fileStatusFromTransactions(file.metadataTx, file.dataTx);
    return status != TransactionStatus.failed &&
        status != TransactionStatus.pending;
  }
}

/// What publishing a scope would show and leave out (docs/PUBLICATIONS.md,
/// "Step 1 · What's included").
class PublicationSummary extends Equatable {
  const PublicationSummary({
    required this.fileCount,
    required this.folderCount,
    required this.totalSize,
    required this.hiddenItems,
    required this.inHiddenFolders,
    required this.inGhostFolders,
    required this.pendingFiles,
    required this.failedFiles,
  });

  /// Files and folders the publication lists, below its top folder, and the
  /// files' total size.
  final int fileCount;
  final int folderCount;
  final int totalSize;

  /// Hidden files and folders directly in what it shows.
  final int hiddenItems;

  /// Files inside a hidden folder.
  final int inHiddenFolders;

  /// Files inside a folder whose own details were never found (a ghost
  /// folder), which the explorer does not list.
  final int inGhostFolders;

  /// Files whose latest upload is not confirmed yet, or failed.
  final int pendingFiles;
  final int failedFiles;

  bool get isEmpty => fileCount == 0;

  bool get leavesOut =>
      hiddenItems +
          inHiddenFolders +
          inGhostFolders +
          pendingFiles +
          failedFiles >
      0;

  @override
  List<Object?> get props => [
        fileCount,
        folderCount,
        totalSize,
        hiddenItems,
        inHiddenFolders,
        inGhostFolders,
        pendingFiles,
        failedFiles,
      ];
}

extension PublicationContentsSummary on PublicationContents {
  /// Counts what [files] lists and why the rest is left out. Ghost folders
  /// are not counted: the explorer never lists them, so an owner has nothing
  /// to recognise.
  PublicationSummary summarize() {
    var files = 0, size = 0, hidden = 0, inHidden = 0, inGhost = 0;
    var pending = 0, failed = 0;
    var folders = 0;
    for (final folder in _folders.values) {
      if (folder.id == _scopeRootFolderId || folder.isGhost) continue;
      if (showsFolder(folder.id)) {
        folders++;
      } else if (folder.isHidden &&
          folder.parentFolderId != null &&
          showsFolder(folder.parentFolderId!)) {
        hidden++;
      }
    }
    for (final file in _files.values) {
      if (!_underScope(file.parentFolderId)) continue;
      if (!showsFolder(file.parentFolderId)) {
        if (_underGhost(file.parentFolderId)) {
          inGhost++;
        } else {
          inHidden++;
        }
      } else if (file.isHidden) {
        hidden++;
      } else {
        switch (fileStatusFromTransactions(file.metadataTx, file.dataTx)) {
          case TransactionStatus.pending:
            pending++;
          case TransactionStatus.failed:
            failed++;
          default:
            files++;
            size += file.size;
        }
      }
    }
    return PublicationSummary(
      fileCount: files,
      folderCount: folders,
      totalSize: size,
      hiddenItems: hidden,
      inHiddenFolders: inHidden,
      inGhostFolders: inGhost,
      pendingFiles: pending,
      failedFiles: failed,
    );
  }

  /// Every file the publication lists, with its path below the top folder,
  /// for `files.html`, folders first by name as a reader browses.
  List<({List<String> path, String dataTxId})> listedFiles() {
    final listed = <({List<String> path, String dataTxId})>[];
    for (final file in files) {
      final path = <String>[file.name];
      String? current = file.parentFolderId;
      for (var depth = 0;
          current != null && current != _scopeRootFolderId && depth < _maxDepth;
          depth++) {
        final folder = _folders[current];
        if (folder == null) break;
        path.insert(0, folder.name);
        current = folder.parentFolderId;
      }
      listed.add((path: path, dataTxId: file.dataTxId));
    }
    listed.sort((a, b) => a.path.join('/').compareTo(b.path.join('/')));
    return listed;
  }

  /// Whether [folderId] or a folder above it, below the top folder, is a
  /// ghost folder.
  bool _underGhost(String folderId) {
    String? current = folderId;
    for (var depth = 0;
        current != null && current != _scopeRootFolderId && depth < _maxDepth;
        depth++) {
      final folder = _folders[current];
      if (folder == null || folder.isGhost) return true;
      current = folder.parentFolderId;
    }
    return false;
  }

  /// Whether [folderId] is the top folder or below it, hidden or not.
  bool _underScope(String folderId) {
    String? current = folderId;
    for (var depth = 0; current != null && depth < _maxDepth; depth++) {
      if (current == _scopeRootFolderId) return true;
      if (current == _rootFolderId) return false;
      current = _folders[current]?.parentFolderId;
    }
    return false;
  }
}

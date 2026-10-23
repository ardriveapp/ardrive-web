import 'package:ardrive/library/domain/library_config.dart';
import 'package:ardrive/models/models.dart';
import 'package:equatable/equatable.dart';

/// What the cover band says about a library: "N files · size".
class LibraryStats extends Equatable {
  const LibraryStats({required this.fileCount, required this.totalSize});

  final int fileCount;
  final int totalSize;

  @override
  List<Object?> get props => [fileCount, totalSize];
}

/// Counts the files a library shows: in its scope, not hidden, and not inside
/// a hidden folder below the published one, as the explorer shows them.
///
/// Read once, after the import, from two queries over the drive rather than
/// one per folder: a folder library's membership is a walk up the parents,
/// done here in memory.
Future<LibraryStats> computeLibraryStats(
  DriveDao driveDao,
  LibraryConfig config,
) async {
  final db = driveDao.attachedDatabase;
  final folders = await (db.select(db.folderEntries)
        ..where((f) => f.driveId.equals(config.driveId)))
      .get();
  final files = await (db.select(db.fileEntries)
        ..where((f) => f.driveId.equals(config.driveId)))
      .get();

  final byId = {for (final f in folders) f.id: f};
  final scopeRoot = config.scopeRootFolderId;
  final shown = <String, bool>{};

  bool isShown(String folderId) {
    final known = shown[folderId];
    if (known != null) return known;
    // Walk up, remembering the path, so each folder is decided once.
    final path = <String>[];
    String? current = folderId;
    var answer = false;
    while (current != null && path.length < 256) {
      final cached = shown[current];
      if (cached != null) {
        answer = cached;
        break;
      }
      final folder = byId[current];
      if (folder == null) break;
      path.add(current);
      if (folder.id == scopeRoot) {
        answer = true;
        break;
      }
      if (folder.isHidden || folder.id == config.rootFolderId) break;
      current = folder.parentFolderId;
    }
    for (final id in path) {
      shown[id] = answer;
    }
    return answer;
  }

  var count = 0;
  var size = 0;
  for (final file in files) {
    if (file.isHidden || !isShown(file.parentFolderId)) continue;
    count++;
    size += file.size;
  }
  return LibraryStats(fileCount: count, totalSize: size);
}

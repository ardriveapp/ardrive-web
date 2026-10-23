import 'package:ardrive/library/domain/library_config.dart';
import 'package:ardrive/library/domain/library_scope.dart';
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
/// one per folder (see [LibraryFolders]).
Future<LibraryStats> computeLibraryStats(
  DriveDao driveDao,
  LibraryConfig config,
) async {
  final db = driveDao.attachedDatabase;
  final folders = await LibraryFolders.load(driveDao, config);
  final files = await (db.select(db.fileEntries)
        ..where((f) => f.driveId.equals(config.driveId)))
      .get();

  var count = 0;
  var size = 0;
  for (final file in files) {
    if (!folders.showsFile(
      isHidden: file.isHidden,
      parentFolderId: file.parentFolderId,
    )) continue;
    count++;
    size += file.size;
  }
  return LibraryStats(fileCount: count, totalSize: size);
}

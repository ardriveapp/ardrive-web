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

/// Counts the files a library lists (see [LibraryContents]). Read once,
/// after the import.
Future<LibraryStats> computeLibraryStats(
  DriveDao driveDao,
  LibraryConfig config,
) async {
  final contents = await LibraryContents.load(driveDao, config);
  var count = 0;
  var size = 0;
  for (final file in contents.files) {
    count++;
    size += file.size;
  }
  return LibraryStats(fileCount: count, totalSize: size);
}

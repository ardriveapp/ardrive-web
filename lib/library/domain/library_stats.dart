import 'package:ardrive/library/domain/library_config.dart';
import 'package:ardrive/library/domain/library_scope.dart';
import 'package:ardrive/models/models.dart';
import 'package:equatable/equatable.dart';

/// What the cover band says about a library: "N files • size".
class LibraryStats extends Equatable {
  const LibraryStats({required this.fileCount, required this.totalSize});

  /// The files [contents] lists, and their total size.
  factory LibraryStats.of(LibraryContents contents) {
    var count = 0;
    var size = 0;
    for (final file in contents.files) {
      count++;
      size += file.size;
    }
    return LibraryStats(fileCount: count, totalSize: size);
  }

  final int fileCount;
  final int totalSize;

  @override
  List<Object?> get props => [fileCount, totalSize];
}

/// Counts the files a library lists (see [LibraryContents]).
Future<LibraryStats> computeLibraryStats(
  DriveDao driveDao,
  LibraryConfig config,
) async =>
    LibraryStats.of(await LibraryContents.load(driveDao, config));

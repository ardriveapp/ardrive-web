import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/publication/domain/publication_scope.dart';
import 'package:ardrive/models/models.dart';
import 'package:equatable/equatable.dart';

/// What the cover band says about a publication: "N files • size".
class PublicationStats extends Equatable {
  const PublicationStats({required this.fileCount, required this.totalSize});

  /// The files [contents] lists, and their total size.
  factory PublicationStats.of(PublicationContents contents) {
    var count = 0;
    var size = 0;
    for (final file in contents.files) {
      count++;
      size += file.size;
    }
    return PublicationStats(fileCount: count, totalSize: size);
  }

  final int fileCount;
  final int totalSize;

  @override
  List<Object?> get props => [fileCount, totalSize];
}

/// Counts the files a publication lists (see [PublicationContents]).
Future<PublicationStats> computePublicationStats(
  DriveDao driveDao,
  PublicationConfig config,
) async =>
    PublicationStats.of(await PublicationContents.load(driveDao, config));

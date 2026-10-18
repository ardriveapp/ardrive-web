import 'package:equatable/equatable.dart';

/// Which of the reader's drives a search could look inside.
///
/// Search reads the database on this device, so it finds files and folders
/// only in drives whose contents are here. A drive discovered at login but
/// never synced is in the drives table by name and nothing else: its name
/// matches, its files never do. Without this, a search that skipped four of six
/// drives looked exactly like one that found nothing in them.
class SearchCoverage extends Equatable {
  const SearchCoverage({
    required this.totalDrives,
    this.unsearchedDriveIds = const [],
  });

  /// Before anything has been counted: claims nothing, so shows nothing.
  static const unknown = SearchCoverage(totalDrives: 0);

  /// The drives in scope: every drive, less hidden ones while hidden items
  /// are hidden.
  final int totalDrives;

  /// The drives in scope whose files and folders search cannot see, because
  /// they are not on this device or their last sync failed.
  final List<String> unsearchedDriveIds;

  int get searchedDrives => totalDrives - unsearchedDriveIds.length;

  bool get isComplete => unsearchedDriveIds.isEmpty;

  @override
  List<Object?> get props => [totalDrives, unsearchedDriveIds];
}

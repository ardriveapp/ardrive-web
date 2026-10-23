part of 'library_loader_cubit.dart';

@immutable
sealed class LibraryLoaderState extends Equatable {
  const LibraryLoaderState();

  @override
  List<Object?> get props => [];
}

/// Reading `library.json`. The screen shows only its background: there is
/// no icon or title yet, and the request is a small one.
class LibraryLoadingSettings extends LibraryLoaderState {
  const LibraryLoadingSettings();
}

/// A private library, waiting for its drive key (the unlock screen).
class LibraryNeedsKey extends LibraryLoaderState {
  const LibraryNeedsKey(this.config);

  final LibraryConfig config;

  @override
  List<Object?> get props => [config];
}

/// Downloading the snapshot. "Loading files…", with how much has arrived and,
/// when the gateway says, of how much.
class LibraryLoadingSnapshot extends LibraryLoaderState {
  const LibraryLoadingSnapshot(
    this.config, {
    required this.received,
    required this.total,
  });

  final LibraryConfig config;
  final int received;
  final int? total;

  @override
  List<Object?> get props => [config, received, total];
}

/// Importing the snapshot. "Almost there…"
class LibraryImporting extends LibraryLoaderState {
  const LibraryImporting(this.config);

  final LibraryConfig config;

  @override
  List<Object?> get props => [config];
}

/// The library is in the database; the explorer opens at its root.
class LibraryReady extends LibraryLoaderState {
  const LibraryReady(this.config, {this.stats});

  final LibraryConfig config;

  /// For the cover band. Null if it could not be counted, which the band
  /// survives by leaving the line out.
  final LibraryStats? stats;

  @override
  List<Object?> get props => [config, stats];
}

/// One of the design's four error screens. [config] is set once
/// `library.json` has been read, so the screen can show the library's title
/// and icon.
class LibraryFailed extends LibraryLoaderState {
  const LibraryFailed(this.failure, {this.config});

  final LibraryFailure failure;
  final LibraryConfig? config;

  @override
  List<Object?> get props => [failure, config];
}

/// docs/LIBRARY_PAGES.md, "Error screens".
enum LibraryFailure {
  /// "This library can't be opened. Its settings are missing or damaged."
  settingsUnreadable,

  /// "This library can't load right now." The one failure worth retrying.
  snapshotUnavailable,

  /// "This library can't be opened. Its data didn't pass ArDrive's checks."
  snapshotRejected,

  /// "This library needs a newer ArDrive."
  needsNewerViewer,
}

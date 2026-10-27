part of 'publication_loader_cubit.dart';

@immutable
sealed class PublicationLoaderState extends Equatable {
  const PublicationLoaderState();

  @override
  List<Object?> get props => [];
}

/// Reading `publication.json`. The screen shows only its background: there is
/// no icon or title yet, and the request is a small one.
class PublicationLoadingSettings extends PublicationLoaderState {
  const PublicationLoadingSettings();
}

/// A private publication, waiting for its drive key (the unlock screen).
class PublicationNeedsKey extends PublicationLoaderState {
  const PublicationNeedsKey(this.config);

  final PublicationConfig config;

  @override
  List<Object?> get props => [config];
}

/// Downloading the snapshot. "Loading files…", with how much has arrived and,
/// when the gateway says, of how much.
class PublicationLoadingSnapshot extends PublicationLoaderState {
  const PublicationLoadingSnapshot(
    this.config, {
    required this.received,
    required this.total,
  });

  final PublicationConfig config;
  final int received;
  final int? total;

  @override
  List<Object?> get props => [config, received, total];
}

/// Importing the snapshot. "Almost there…"
class PublicationImporting extends PublicationLoaderState {
  const PublicationImporting(this.config);

  final PublicationConfig config;

  @override
  List<Object?> get props => [config];
}

/// The publication is in the database; the explorer opens at its root.
class PublicationReady extends PublicationLoaderState {
  const PublicationReady(this.config, {this.stats, this.ownerVerified = false});

  final PublicationConfig config;

  /// Whether the serving gateway confirmed the snapshot was signed by
  /// [PublicationConfig.owner]; false when it could not say (a mismatch
  /// never gets this far). The byline shows the owner either way.
  final bool ownerVerified;

  /// For the header's byline. Null if it could not be counted, which the
  /// byline survives by leaving the counts out.
  final PublicationStats? stats;

  @override
  List<Object?> get props => [config, stats, ownerVerified];
}

/// One of the design's four error screens. [config] is set once
/// `publication.json` has been read, so the screen can show the publication's title
/// and icon.
class PublicationFailed extends PublicationLoaderState {
  const PublicationFailed(this.failure, {this.config});

  final PublicationFailure failure;
  final PublicationConfig? config;

  @override
  List<Object?> get props => [failure, config];
}

/// docs/PUBLICATIONS.md, "Error screens".
enum PublicationFailure {
  /// "This page can't be opened. Its settings are missing or damaged."
  settingsUnreadable,

  /// "This page can't load right now." The one failure worth retrying.
  snapshotUnavailable,

  /// "This page can't be opened. Its data didn't pass ArDrive's checks."
  snapshotRejected,

  /// "This page needs a newer ArDrive."
  needsNewerViewer,
}

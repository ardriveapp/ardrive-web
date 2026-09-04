import 'package:ardrive/sync/domain/sync_trigger.dart';

/// How many finished syncs are kept.
///
/// A cap rather than a growing log, because this is written to the same flat
/// key-value store everything else the app persists shares, and an uncapped
/// list of every sync a long-lived session runs would grow without anything
/// ever trimming it. Twenty is about a day of background syncs at the shipped
/// interval, which is the span a "what happened this morning" question covers;
/// past that, the diagnostic logs beside it in the same modal are the record.
const int syncHistoryLimit = 20;

/// How a sync ended.
///
/// Four outcomes, and every one of them is a thing a user can be told. A run
/// that never started - a hidden tab, an upload in the way, a second request
/// while one was already running - is not in here at all: nothing was fetched,
/// so there is nothing to report about it.
enum SyncRunOutcome {
  /// Ran to the end, every drive read.
  completed,

  /// Ran to the end, some drives could not be read.
  completedWithErrors,

  /// Could not be done at all - the drive list itself, usually.
  failed,

  /// Stopped part way.
  cancelled,
}

/// One finished sync, written down so the user can look at it later.
///
/// Everything here is read off what the sync already reported. Nothing is
/// recounted, no drive is queried again, and building one costs no network
/// request - see `SyncCubit._recordSyncRun`.
class SyncRun {
  const SyncRun({
    required this.startedAt,
    required this.took,
    required this.trigger,
    required this.outcome,
    this.driveName,
    this.itemsFound = 0,
    this.skippedEntityCount = 0,
    this.failedDrives = 0,
    this.totalDrives = 0,
    this.errorMessages = const {},
  });

  /// When the sync began - `SyncCubit.syncStartTime`, the same instant the
  /// elapsed counter on the indicator was counting from.
  final DateTime startedAt;

  /// How long it took, start to finish.
  final Duration took;

  /// Who asked for it.
  final SyncTrigger trigger;

  /// The drive this sync was for, when it was for one drive. Null for a sync
  /// of every drive, which is what the two triggers above describe on their
  /// own.
  final String? driveName;

  /// Files and folders this sync wrote.
  final int itemsFound;

  /// Entities dropped because their metadata could not be read.
  final int skippedEntityCount;

  final SyncRunOutcome outcome;

  /// How many drives could not be read, out of how many were walked.
  final int failedDrives;
  final int totalDrives;

  /// What went wrong, keyed by the drive it went wrong on.
  ///
  /// The text the sync layer produced, kept verbatim. A user reading this is
  /// about to send the logs sitting beside it to support, and a message this
  /// surface paraphrased is a message support cannot search for.
  final Map<String, String> errorMessages;

  /// Whether this run has anything to say beyond "it finished".
  bool get hasProblems =>
      outcome != SyncRunOutcome.completed || skippedEntityCount > 0;

  Map<String, dynamic> toJson() => {
        'startedAt': startedAt.millisecondsSinceEpoch,
        'tookMs': took.inMilliseconds,
        'trigger': trigger.name,
        'outcome': outcome.name,
        if (driveName != null) 'driveName': driveName,
        'itemsFound': itemsFound,
        'skipped': skippedEntityCount,
        'failedDrives': failedDrives,
        'totalDrives': totalDrives,
        if (errorMessages.isNotEmpty) 'errors': errorMessages,
      };

  /// One stored run, or null if it cannot be read.
  ///
  /// Null rather than a default-filled entry: an unreadable record is dropped,
  /// because a row of zeroes claiming a clean sync is worse than a row that is
  /// not there. The rest of the list is kept - one bad entry written by an
  /// older build must not throw the history away.
  static SyncRun? tryFromJson(Object? stored) {
    if (stored is! Map) {
      return null;
    }

    final startedAt = stored['startedAt'];
    final tookMs = stored['tookMs'];

    if (startedAt is! int || tookMs is! int) {
      return null;
    }

    final outcome = _byName(SyncRunOutcome.values, stored['outcome']);
    final trigger = _byName(SyncTrigger.values, stored['trigger']);

    if (outcome == null || trigger == null) {
      return null;
    }

    final errors = stored['errors'];

    return SyncRun(
      startedAt: DateTime.fromMillisecondsSinceEpoch(startedAt),
      took: Duration(milliseconds: tookMs),
      trigger: trigger,
      outcome: outcome,
      driveName: stored['driveName'] is String ? stored['driveName'] : null,
      itemsFound: stored['itemsFound'] is int ? stored['itemsFound'] : 0,
      skippedEntityCount: stored['skipped'] is int ? stored['skipped'] : 0,
      failedDrives: stored['failedDrives'] is int ? stored['failedDrives'] : 0,
      totalDrives: stored['totalDrives'] is int ? stored['totalDrives'] : 0,
      errorMessages: errors is Map
          ? {
              for (final entry in errors.entries)
                if (entry.key is String && entry.value is String)
                  entry.key as String: entry.value as String,
            }
          : const {},
    );
  }

  static T? _byName<T extends Enum>(List<T> values, Object? name) {
    for (final value in values) {
      if (value.name == name) {
        return value;
      }
    }

    return null;
  }
}

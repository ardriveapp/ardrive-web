import 'package:ardrive/sync/domain/sync_run.dart';
import 'package:ardrive/sync/domain/sync_trigger.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// The key the panel hangs off, so a test can find it whatever it is showing.
const Key syncHistoryPanelKey = Key('syncHistoryPanel');

/// Level two: what the recent syncs actually did.
///
/// It lives inside the Troubleshooting section of the support modal, which is
/// already the surface for "something is wrong" and already carries the
/// diagnostic logs a user with a problem is about to send. Nothing here is on
/// screen unasked, and nothing here is asked for until the modal is opened -
/// the read is a local one and costs no network request.
///
/// Deliberately not in the sync menu. That menu sizes its overlay as
/// `items.length * 48` and closes on any tap inside it, so a list that scrolls
/// could not live there; the menu carries one row that opens this instead.
class SyncHistoryPanel extends StatefulWidget {
  const SyncHistoryPanel({super.key, this.now});

  /// The instant "12 minutes ago" is counted back from. Injected so a test can
  /// pin it; [DateTime.now] otherwise.
  final DateTime? now;

  @override
  State<SyncHistoryPanel> createState() => _SyncHistoryPanelState();
}

class _SyncHistoryPanelState extends State<SyncHistoryPanel> {
  /// Held in a field, not started in `build`: a future rebuilt on every frame
  /// re-reads the store forever and never settles.
  late final Future<List<SyncRun>> _history;

  @override
  void initState() {
    super.initState();
    _history = context.read<UserPreferencesRepository>().loadSyncHistory();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SyncRun>>(
      key: syncHistoryPanelKey,
      future: _history,
      builder: (context, snapshot) {
        // A local key-value read, so this is a frame at most. Nothing is drawn
        // in the meantime rather than a spinner or a premature "nothing yet",
        // either of which would be a claim the panel cannot make yet.
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }

        final runs = snapshot.data ?? const <SyncRun>[];

        if (runs.isEmpty) {
          return const _NothingYet();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final run in runs)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SyncRunTile(run: run, now: widget.now),
              ),
          ],
        );
      },
    );
  }
}

/// A wallet that has never synced on this device.
///
/// Two lines, and neither of them is an error: nothing has happened, which is
/// a fact about a new install rather than a fault, and the second line says
/// what would fill the list so it does not read as broken.
class _NothingYet extends StatelessWidget {
  const _NothingYet();

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          appLocalizationsOf(context).syncHistoryEmpty,
          style: typography.paragraphNormal(color: colorTokens.textHigh),
        ),
        const SizedBox(height: 4),
        Text(
          appLocalizationsOf(context).syncHistoryEmptyDescription,
          style: typography.paragraphSmall(color: colorTokens.textMid),
        ),
      ],
    );
  }
}

/// One finished sync.
///
/// Four lines at most, and each of them is a different fact: what was synced,
/// when and for how long, what it found, and - only when there is one - what
/// went wrong, in the words the sync layer used.
class SyncRunTile extends StatelessWidget {
  const SyncRunTile({super.key, required this.run, this.now});

  final SyncRun run;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final localizations = appLocalizationsOf(context);

    final isProblem = run.outcome != SyncRunOutcome.completed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isProblem) ...[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: ArDriveIcons.triangle(
                  size: 14,
                  color: colorTokens.strokeRed,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                // The drive it was for, by name, or the fact that it was all
                // of them. Never a drive id: an id is not a thing a user
                // recognises.
                run.driveName ?? localizations.syncHistoryAllDrives,
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.semiBold,
                  color: colorTokens.textHigh,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          localizations.syncHistoryRunSummary(
            formatSyncRunStartedAt(context, run, now: now),
            formatSyncRunTrigger(context, run),
            formatSyncRunDuration(context, run),
          ),
          style: typography.paragraphSmall(color: colorTokens.textMid),
        ),
        for (final line in syncRunOutcomeLines(localizations, run))
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              line,
              style: typography.paragraphSmall(
                color: isProblem ? colorTokens.textRed : colorTokens.textMid,
              ),
            ),
          ),
        // Verbatim, and never shortened. The user reading this is one button
        // away from sending the logs beside it to support, and a message this
        // panel paraphrased is a message support cannot search for.
        for (final message in run.errorMessages.values)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              message,
              style: typography.paragraphSmall(color: colorTokens.textRed),
            ),
          ),
      ],
    );
  }
}

/// When this sync started, said the way the drives list says it.
///
/// Pulled out of the widget so the thresholds can be checked directly. Past a
/// day a date reads better than a count of hours, and it carries the time of
/// day: "which sync was that" is usually a question about this morning.
String formatSyncRunStartedAt(
  BuildContext context,
  SyncRun run, {
  DateTime? now,
}) {
  final elapsed = (now ?? DateTime.now()).difference(run.startedAt);

  if (elapsed.inMinutes < 1) {
    return appLocalizationsOf(context).syncHistoryJustNow;
  }

  if (elapsed.inMinutes < 60) {
    return appLocalizationsOf(context).syncHistoryMinutesAgo(elapsed.inMinutes);
  }

  if (elapsed.inHours < 24) {
    return appLocalizationsOf(context).syncHistoryHoursAgo(elapsed.inHours);
  }

  return DateFormat.yMMMd().add_jm().format(run.startedAt);
}

/// Who asked for this sync.
String formatSyncRunTrigger(BuildContext context, SyncRun run) {
  switch (run.trigger) {
    case SyncTrigger.background:
      return appLocalizationsOf(context).syncHistoryTriggerAutomatic;
    case SyncTrigger.userInitiated:
      return appLocalizationsOf(context).syncHistoryTriggerManual;
  }
}

/// How long it took.
///
/// Seconds under a minute, minutes and seconds above: a sync that took eleven
/// minutes is the whole point of writing this down, and "660s" is not a
/// number anybody reads.
String formatSyncRunDuration(BuildContext context, SyncRun run) {
  final seconds = run.took.inSeconds;

  if (seconds < 60) {
    return appLocalizationsOf(context)
        .syncHistoryDurationSeconds(seconds.toString());
  }

  return appLocalizationsOf(context).syncHistoryDurationMinutes(
    (seconds ~/ 60).toString(),
    (seconds % 60).toString(),
  );
}

/// What this run found, and what it could not.
///
/// A list rather than one line because the two are independent: a sync can
/// finish cleanly and still have dropped files whose metadata would not load,
/// and a user who is not told that is looking at a drive with holes in it and
/// a panel saying everything went well.
List<String> syncRunOutcomeLines(AppLocalizations localizations, SyncRun run) {
  final lines = <String>[];

  switch (run.outcome) {
    case SyncRunOutcome.completed:
      lines.add(localizations.syncHistoryFoundItems(run.itemsFound));
    case SyncRunOutcome.completedWithErrors:
      lines.add(localizations.syncHistoryFoundItems(run.itemsFound));
      lines.add(localizations.syncDrivesFailed(
        run.failedDrives,
        run.totalDrives,
      ));
    case SyncRunOutcome.failed:
      lines.add(localizations.syncHistoryFailedDetail);
    case SyncRunOutcome.cancelled:
      lines.add(localizations.syncHistoryCancelledDetail);
  }

  if (run.skippedEntityCount > 0) {
    lines.add(localizations.syncHistorySkipped(run.skippedEntityCount));
  }

  return lines;
}

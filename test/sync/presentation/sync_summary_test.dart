import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/presentation/sync_summary.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The line a finished sync gets to say for itself. Every case has to read as
/// a sentence someone would write - most of all the one where nothing changed,
/// which is the sync the user most needs to learn they can ignore next time.
void main() {
  group('how long a result is entitled to', () {
    SyncComplete completedAgo(Duration ago) => SyncComplete(
          entitiesSynced: 0,
          skippedEntityCount: 0,
          isSingleDriveSync: false,
          driveName: null,
          trigger: SyncTrigger.background,
          completedAt: DateTime.now().subtract(ago),
          sequence: 1,
        );

    test('a fresh result gets the whole window', () {
      final remaining = syncSummaryRemaining(completedAgo(Duration.zero));
      expect(remaining.inMilliseconds,
          closeTo(syncSummaryDuration.inMilliseconds, 100));
    });

    test('a result built near the boundary gets only what is left', () {
      // The defect this guards: a surface that started a fresh
      // syncSummaryDuration timer here would show the result for nearly twice
      // its entitlement.
      final remaining = syncSummaryRemaining(
        completedAgo(syncSummaryDuration - const Duration(milliseconds: 200)),
      );
      expect(remaining, lessThan(const Duration(milliseconds: 400)));
      expect(remaining, greaterThan(Duration.zero));
    });

    test('an expired result gets nothing, never a negative', () {
      expect(
        syncSummaryRemaining(completedAgo(const Duration(hours: 1))),
        Duration.zero,
      );
    });
  });

  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  SyncComplete finished({
    int entitiesSynced = 0,
    int skippedEntityCount = 0,
    bool isSingleDriveSync = false,
    String? driveName,
  }) =>
      SyncComplete(
        entitiesSynced: entitiesSynced,
        skippedEntityCount: skippedEntityCount,
        isSingleDriveSync: isSingleDriveSync,
        driveName: driveName,
        completedAt: DateTime(2026, 8, 29),
        sequence: 1,
      );

  String summaryOf(SyncComplete state) => syncCompleteSummary(l10n, state);

  SyncSummary partsOf(SyncComplete state) =>
      syncCompleteSummaryParts(l10n, state);

  test('a sync that changed nothing says so', () {
    expect(summaryOf(finished()), 'Up to date — nothing new');
  });

  test('a sync of one named drive that changed nothing names it', () {
    expect(
      summaryOf(finished(isSingleDriveSync: true, driveName: 'Photos')),
      'Photos is up to date — nothing new',
    );
  });

  test('a single drive sync with no name to give still says nothing is new',
      () {
    expect(
      summaryOf(finished(isSingleDriveSync: true)),
      'Up to date — nothing new',
    );
  });

  test('the count of what arrived is the whole claim', () {
    expect(summaryOf(finished(entitiesSynced: 12)), '12 items changed');
  });

  test('a single new item is not "1 items changed"', () {
    expect(summaryOf(finished(entitiesSynced: 1)), '1 item changed');
  });

  test('a sync of every drive does not say how many drives it walked', () {
    // It used to say "12 items changed across 3 drives". That number counted
    // drives *walked*, failures included: twelve files that all landed in one
    // drive sent the user looking through three, and "1 item changed across 3
    // drives" is not a thing that can happen. The sync does not know the
    // number that sentence implied, so it stopped implying it.
    expect(summaryOf(finished(entitiesSynced: 12)), '12 items changed');
    expect(summaryOf(finished(entitiesSynced: 12)), isNot(contains('across')));
    expect(summaryOf(finished(entitiesSynced: 12)), isNot(contains('drive')));
  });

  test('a sync of one named drive names it', () {
    expect(
      summaryOf(finished(
        entitiesSynced: 12,
        isSingleDriveSync: true,
        driveName: 'Photos',
      )),
      '12 items changed in Photos',
    );
  });

  test('items that could not be read are said out loud', () {
    // These are files the user will not see. A summary that counted only what
    // arrived would report a clean sync over a drive with holes in it.
    expect(
      summaryOf(finished(entitiesSynced: 12, skippedEntityCount: 2)),
      '12 items changed · 2 updates could not be read',
    );
  });

  test('one item that could not be read is not "1 items"', () {
    expect(
      summaryOf(finished(entitiesSynced: 12, skippedEntityCount: 1)),
      '12 items changed · 1 update could not be read',
    );
  });

  test('nothing arrived and something was unreadable is not "up to date"', () {
    // Nothing was written, but the sync cannot claim the drive is current:
    // what it could not read is exactly what is missing.
    expect(
      summaryOf(finished(skippedEntityCount: 2)),
      '2 updates could not be read',
    );
  });

  group('the two halves stay separable', () {
    // A surface with a width limit has to be able to shorten what arrived
    // without shortening what could not be read - joined into one string the
    // unreadable clause comes last, and is the first thing an ellipsis eats.
    test('what could not be read is a part of its own', () {
      final parts =
          partsOf(finished(entitiesSynced: 12, skippedEntityCount: 2));

      expect(parts.arrived, '12 items changed');
      expect(parts.unreadable, '2 updates could not be read');
      expect(parts.lines, ['12 items changed', '2 updates could not be read']);
    });

    test('a clean sync has nothing unreadable to say', () {
      final parts = partsOf(finished(entitiesSynced: 12));

      expect(parts.arrived, '12 items changed');
      expect(parts.unreadable, isNull);
      expect(parts.lines, ['12 items changed']);
    });

    test('nothing arrived leaves only the unreadable line', () {
      final parts = partsOf(finished(skippedEntityCount: 2));

      expect(parts.arrived, isNull);
      expect(parts.lines, ['2 updates could not be read']);
    });
  });

  group('a stale result is not a result', () {
    // SyncComplete stays the cubit's state until the next sync runs, and both
    // surfaces start their countdown when they are built. Rebuilding one an
    // hour later must not announce a sync that finished an hour ago.
    final finishedAt = DateTime(2026, 8, 29, 12);
    final result = SyncComplete(
      entitiesSynced: 3,
      completedAt: finishedAt,
      sequence: 1,
    );

    test('a result that just landed is fresh', () {
      expect(syncSummaryIsFresh(result, now: finishedAt), isTrue);
    });

    test('a result is fresh right up to the end of its few seconds', () {
      expect(
        syncSummaryIsFresh(
          result,
          now: finishedAt.add(syncSummaryDuration - const Duration(seconds: 1)),
        ),
        isTrue,
      );
    });

    test('a result that has had its time is not shown again', () {
      expect(
        syncSummaryIsFresh(result, now: finishedAt.add(syncSummaryDuration)),
        isFalse,
      );
      expect(
        syncSummaryIsFresh(
          result,
          now: finishedAt.add(const Duration(hours: 1)),
        ),
        isFalse,
      );
    });
  });
}

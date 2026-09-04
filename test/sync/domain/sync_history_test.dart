import 'dart:convert';

import 'package:ardrive/sync/domain/sync_run.dart';
import 'package:ardrive/sync/domain/sync_trigger.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../core/upload/uploader_test.dart';

class _MockThemeDetector extends Mock implements ThemeDetector {}

/// The key-value store, in memory. A mock would have to be told the answer to
/// every read, which is exactly the part under test here: what comes back out
/// after something has gone in.
class _FakeStore implements LocalKeyValueStore {
  final Map<String, Object> _values = {};

  @override
  bool? getBool(String key) => _values[key] as bool?;

  @override
  String? getString(String key) => _values[key] as String?;

  @override
  Set<String> getKeys() => _values.keys.toSet();

  @override
  Future<bool> putBool(String key, bool value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> putString(String key, String value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    _values.remove(key);
    return true;
  }
}

void main() {
  late _FakeStore store;
  late UserPreferencesRepository repository;
  late MockArDriveAuth auth;

  SyncRun run({
    required DateTime startedAt,
    Duration took = const Duration(seconds: 8),
    SyncTrigger trigger = SyncTrigger.background,
    SyncRunOutcome outcome = SyncRunOutcome.completed,
    String? driveName,
    int itemsFound = 0,
    int skippedEntityCount = 0,
    int failedDrives = 0,
    int totalDrives = 0,
    Map<String, String> errorMessages = const {},
  }) =>
      SyncRun(
        startedAt: startedAt,
        took: took,
        trigger: trigger,
        outcome: outcome,
        driveName: driveName,
        itemsFound: itemsFound,
        skippedEntityCount: skippedEntityCount,
        failedDrives: failedDrives,
        totalDrives: totalDrives,
        errorMessages: errorMessages,
      );

  setUp(() {
    store = _FakeStore();
    auth = MockArDriveAuth();
    final themeDetector = _MockThemeDetector();

    when(() => themeDetector.getOSDefaultTheme())
        .thenReturn(ArDriveThemes.light);
    when(() => auth.onAuthStateChanged())
        .thenAnswer((_) => Stream.value(getFakeUser()));

    repository = UserPreferencesRepository(
      store: store,
      themeDetector: themeDetector,
      auth: auth,
    );
  });

  test('a wallet that has never synced has an empty history, not an error',
      () async {
    expect(await repository.loadSyncHistory(), isEmpty);
  });

  test('a recorded run comes back with every fact it went in with', () async {
    final startedAt = DateTime(2026, 8, 31, 9, 15);

    await repository.recordSyncRun(run(
      startedAt: startedAt,
      took: const Duration(minutes: 2, seconds: 14),
      trigger: SyncTrigger.userInitiated,
      outcome: SyncRunOutcome.completedWithErrors,
      driveName: 'Family Photos',
      itemsFound: 12,
      skippedEntityCount: 3,
      failedDrives: 2,
      totalDrives: 5,
      errorMessages: const {'drive-a': 'the gateway said no'},
    ));

    final history = await repository.loadSyncHistory();

    expect(history, hasLength(1));
    expect(history.single.startedAt, startedAt);
    expect(history.single.took, const Duration(minutes: 2, seconds: 14));
    expect(history.single.trigger, SyncTrigger.userInitiated);
    expect(history.single.outcome, SyncRunOutcome.completedWithErrors);
    expect(history.single.driveName, 'Family Photos');
    expect(history.single.itemsFound, 12);
    expect(history.single.skippedEntityCount, 3);
    expect(history.single.failedDrives, 2);
    expect(history.single.totalDrives, 5);
    expect(history.single.errorMessages, {'drive-a': 'the gateway said no'});
  });

  test('the most recent run is first', () async {
    for (var minute = 0; minute < 3; minute++) {
      await repository.recordSyncRun(
        run(startedAt: DateTime(2026, 8, 31, 9, minute)),
      );
    }

    final history = await repository.loadSyncHistory();

    expect(
      history.map((entry) => entry.startedAt.minute).toList(),
      [2, 1, 0],
    );
  });

  test('it survives a reload, because it is on disk and not in memory',
      () async {
    await repository.recordSyncRun(
      run(startedAt: DateTime(2026, 8, 31, 9), itemsFound: 12),
    );

    // A second repository over the same store is what a page reload looks
    // like: nothing is carried across in memory.
    final freshDetector = _MockThemeDetector();
    when(() => freshDetector.getOSDefaultTheme())
        .thenReturn(ArDriveThemes.light);

    final afterReload = UserPreferencesRepository(
      store: store,
      themeDetector: freshDetector,
      auth: auth,
    );

    final history = await afterReload.loadSyncHistory();

    expect(history, hasLength(1));
    expect(history.single.itemsFound, 12);
  });

  test('it keeps $syncHistoryLimit runs and drops the oldest', () async {
    // Five more than the cap, so the drop is not a coincidence of the count.
    for (var minute = 0; minute < syncHistoryLimit + 5; minute++) {
      await repository.recordSyncRun(
        run(startedAt: DateTime(2026, 8, 31, 9, minute), itemsFound: minute),
      );
    }

    final history = await repository.loadSyncHistory();

    expect(history, hasLength(syncHistoryLimit));
    expect(history.first.itemsFound, syncHistoryLimit + 4,
        reason: 'the newest run is kept');
    expect(history.last.itemsFound, 5, reason: 'the oldest five are dropped');

    // And trimmed on the way in, so the stored list cannot grow past the cap
    // however long a session runs.
    final stored = jsonDecode(store.getString('syncHistory')!) as List;
    expect(stored, hasLength(syncHistoryLimit));
  });

  test('logging out takes it with everything else local', () async {
    await repository.recordSyncRun(run(startedAt: DateTime(2026, 8, 31, 9)));
    expect(await repository.loadSyncHistory(), hasLength(1),
        reason: 'precondition: there is something to clear');

    await repository.clear();

    expect(await repository.loadSyncHistory(), isEmpty);
    expect(store.getString('syncHistory'), isNull);
  });

  test('one unreadable entry is dropped, and the rest of the list survives',
      () async {
    await repository.recordSyncRun(
      run(startedAt: DateTime(2026, 8, 31, 9), itemsFound: 7),
    );

    // A record written by a build that spelled something differently. Reading
    // it as a row of zeroes would claim a clean sync that never happened.
    final stored = jsonDecode(store.getString('syncHistory')!) as List;
    await store.putString(
      'syncHistory',
      jsonEncode([
        {'startedAt': 'not a number', 'outcome': 'completed'},
        ...stored,
        {'startedAt': 0, 'tookMs': 0, 'outcome': 'exploded', 'trigger': 'x'},
      ]),
    );

    final history = await repository.loadSyncHistory();

    expect(history, hasLength(1));
    expect(history.single.itemsFound, 7);
  });

  test('a store holding something that is not a list reads as empty', () async {
    await store.putString('syncHistory', '{"not":"a list"}');

    expect(await repository.loadSyncHistory(), isEmpty);
  });
}

import 'dart:async';

import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/drive_detail_syncing_card.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../test_utils/mocks.dart';

/// What the explorer draws while it waits for a folder.
///
/// Every test here disposes the tree itself before finishing: the elapsed
/// counter owns a periodic timer for as long as it is mounted, and a test that
/// walks away from one fails on the pending timer instead of on its subject.
void main() {
  late MockSyncBloc syncCubit;
  late MockDrivesCubit drivesCubit;
  late StreamController<SyncState> syncStates;
  late StreamController<SyncProgress> progress;

  const phoneSize = Size(320, 640);
  const desktopSize = Size(1200, 900);

  setUp(() {
    syncCubit = MockSyncBloc();
    drivesCubit = MockDrivesCubit();
    // Broadcast on purpose - see the same note in sync_button_test.dart.
    syncStates = StreamController<SyncState>.broadcast();
    progress = StreamController<SyncProgress>.broadcast();

    whenListen(syncCubit, syncStates.stream, initialState: SyncIdle());
    when(() => syncCubit.syncProgressController).thenReturn(progress);
    when(() => syncCubit.syncProgress).thenReturn(SyncProgress.initial());
    when(() => syncCubit.syncStartTime).thenReturn(DateTime.now());

    whenListen(
      drivesCubit,
      const Stream<DrivesState>.empty(),
      initialState: DrivesLoadInProgress(),
    );
  });

  tearDown(() async {
    await syncStates.close();
    await progress.close();
  });

  Drive drive({required String id, required String name}) => Drive(
        id: id,
        rootFolderId: '$id-root',
        ownerAddress: 'owner',
        name: name,
        privacy: 'public',
        isHidden: false,
        dateCreated: DateTime(2026),
        lastUpdated: DateTime(2026),
      );

  Widget host(
    Widget body, {
    ArDriveThemeData? theme,
    Size size = phoneSize,
  }) {
    return ArDriveTheme(
      themeData: theme ?? lightTheme(),
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', '')],
        home: Scaffold(
          body: Builder(
            builder: (context) => MediaQuery(
              // `setSurfaceSize` changes the box the tree is laid out in but
              // not what MediaQuery reports, and responsive_builder chooses a
              // layout from MediaQuery. Without this the desktop branch is
              // unreachable from a test and both "platforms" would silently
              // prove the same widget - which is exactly what happened here
              // before a deliberate break said so.
              data: MediaQuery.of(context).copyWith(size: size),
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<SyncCubit>.value(value: syncCubit),
                  BlocProvider<DrivesCubit>.value(value: drivesCubit),
                ],
                child: body,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget wrap({ArDriveThemeData? theme, Size size = phoneSize}) =>
      host(const DriveDetailSyncingCard(), theme: theme, size: size);

  /// Renders the panel at [size] with a background sync already under way -
  /// the case it exists for. A drive clicked mid-sync lands here, so the panel
  /// mounts into a sync rather than watching one start.
  Future<void> pumpSyncing(
    WidgetTester tester, {
    Size size = phoneSize,
    SyncProgress? reporting,
    ArDriveThemeData? theme,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    whenListen(
      syncCubit,
      syncStates.stream,
      initialState: SyncInProgress(trigger: SyncTrigger.background),
    );

    await tester.pumpWidget(wrap(theme: theme, size: size));
    await tester.pump();

    if (reporting != null) {
      progress.add(reporting);
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  /// The bar the panel is filling.
  LinearProgressIndicator bar(WidgetTester tester) =>
      tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );

  /// Selects the drive the user is waiting for.
  void selectDrive(String name) {
    whenListen(
      drivesCubit,
      const Stream<DrivesState>.empty(),
      initialState: DrivesLoadSuccess(
        selectedDriveId: 'drive-1',
        userDrives: [drive(id: 'drive-1', name: name)],
        sharedDrives: const [],
        drivesWithAlerts: const [],
        canCreateNewDrive: true,
      ),
    );
  }

  testWidgets('a background sync is named, not spun at', (tester) async {
    await pumpSyncing(
      tester,
      reporting: SyncProgress.initial().copyWith(
        progress: 0.42,
        statusMessage: 'Downloading drive snapshots...',
      ),
    );

    // What the wait is, in words - the same words the top bar and the modal
    // use for it.
    expect(find.text('Syncing All Drives'), findsOneWidget);
    expect(find.text('Downloading drive snapshots...'), findsOneWidget);
    // How long it has been going on.
    expect(find.textContaining('s elapsed'), findsOneWidget);

    // And a bar that is actually filling, in place of the bare indicator this
    // slot used to hold.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(bar(tester).value, closeTo(0.42, 0.001));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the bar starts where the sync already is', (tester) async {
    // The panel mounts mid-sync by definition, and the cubit replays nothing.
    // Without the seed the bar reads empty until the next progress event -
    // which in the unmeasurable phase is up to half a minute away. No event is
    // published here at all: everything on screen came from the seed.
    when(() => syncCubit.syncProgress).thenReturn(
      SyncProgress.initial().copyWith(
        progress: 0.6,
        statusMessage: 'Downloading drive snapshots...',
      ),
    );

    await pumpSyncing(tester);
    await tester.pump(const Duration(milliseconds: 1100));

    expect(bar(tester).value, closeTo(0.6, 0.001));
    expect(find.text('Downloading drive snapshots...'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the drive being waited for is named', (tester) async {
    selectDrive('Photos');

    await pumpSyncing(
      tester,
      reporting: SyncProgress.initial().copyWith(
        progress: 0.42,
        statusMessage: 'Downloading drive snapshots...',
      ),
    );

    expect(
      find.text('Photos will open when the sync finishes'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a single drive sync names its own drive', (tester) async {
    await pumpSyncing(
      tester,
      reporting: SyncProgress.initial().copyWith(
        progress: 0.42,
        isSingleDriveSync: true,
        driveName: 'Invoices',
        statusMessage: 'Downloading drive snapshots...',
      ),
    );

    expect(find.text('Syncing Drive'), findsOneWidget);
    expect(
      find.text('Invoices will open when the sync finishes'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a phase that cannot measure itself shows no frozen number',
      (tester) async {
    await pumpSyncing(
      tester,
      reporting: SyncProgress.initial().copyWith(progress: 0.97),
    );
    await tester.pump(const Duration(milliseconds: 1100));

    expect(bar(tester).value, closeTo(0.97, 0.001));
    expect(find.text('97% complete'), findsOneWidget);

    // The gateway round trip cannot know its own length, so the bar stops
    // claiming one rather than sitting at 97% until it answers.
    progress.add(SyncProgress.initial().copyWith(
      progress: 0.97,
      isIndeterminate: true,
      statusMessage: 'Updating transaction statuses...',
    ));
    await tester.pump(const Duration(milliseconds: 1100));

    expect(bar(tester).value, isNull);
    expect(find.text('97% complete'), findsNothing);
    expect(find.text('Updating transaction statuses...'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('collecting drive metadata is named, and invents no number',
      (tester) async {
    // The phase before a sync has anything to measure. The top bar calls it
    // "Loading your drives..." and leaves its ring empty; this panel has to
    // agree with it rather than announce a sync at 0%.
    await tester.binding.setSurfaceSize(phoneSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    whenListen(
      syncCubit,
      syncStates.stream,
      initialState: SyncLoadingDrives(),
    );

    await tester.pumpWidget(wrap());
    await tester.pump(const Duration(milliseconds: 1100));

    expect(find.text('Loading your drives...'), findsOneWidget);
    expect(find.text('0% complete'), findsNothing);
    expect(bar(tester).value, isNull);
    // And no stopwatch: only a real sync sets a start time, so counting here
    // counts from whenever the cubit was built - "420s elapsed" under
    // "Loading your drives...". The top bar withholds it for the same reason.
    expect(find.textContaining('s elapsed'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a wait that is not a sync still says what it is',
      (tester) async {
    selectDrive('Photos');

    await tester.binding.setSurfaceSize(phoneSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(find.text('Opening Photos'), findsOneWidget);
    // Nothing to measure, so nothing is claimed - and no elapsed time, which
    // would be counted from a sync that ended long ago.
    expect(bar(tester).value, isNull);
    expect(find.textContaining('s elapsed'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  for (final layout in [
    ('a phone', phoneSize),
    ('a desktop', desktopSize),
  ]) {
    testWidgets('${layout.$1} is told the phase and the progress',
        (tester) async {
      selectDrive('Photos');

      await pumpSyncing(
        tester,
        size: layout.$2,
        reporting: SyncProgress.initial().copyWith(
          progress: 0.42,
          statusMessage: 'Downloading drive snapshots...',
        ),
      );
      await tester.pump(const Duration(milliseconds: 1100));

      expect(find.text('Syncing All Drives'), findsOneWidget);
      expect(
        find.text('Photos will open when the sync finishes'),
        findsOneWidget,
      );
      expect(find.text('Downloading drive snapshots...'), findsOneWidget);
      expect(find.textContaining('s elapsed'), findsOneWidget);
      expect(bar(tester).value, closeTo(0.42, 0.001));

      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final theme in [
    ('light', lightTheme()),
    ('dark', ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode())),
  ]) {
    testWidgets('nothing overflows a 320px phone in ${theme.$1}',
        (tester) async {
      selectDrive('Family Photos And Videos Nineteen Ninety Nine To Today');

      await pumpSyncing(
        tester,
        theme: theme.$2,
        reporting: SyncProgress.initial().copyWith(
          progress: 0.42,
          statusMessage: 'Updating transaction statuses for pending uploads...',
        ),
      );
      await tester.pump(const Duration(milliseconds: 1100));

      expect(tester.takeException(), isNull);

      // Rendered, not merely present: every line has to start on screen and
      // end on screen.
      for (final text in [
        'Syncing All Drives',
        'Family Photos And Videos Nineteen Ninety Nine To Today '
            'will open when the sync finishes',
        'Updating transaction statuses for pending uploads...',
      ]) {
        final finder = find.text(text);
        expect(finder, findsOneWidget, reason: text);
        expect(tester.getTopLeft(finder).dx, greaterThanOrEqualTo(0));
        expect(tester.getBottomRight(finder).dx, lessThanOrEqualTo(320.0));
        expect(
          tester.renderObject<RenderParagraph>(finder).didExceedMaxLines,
          isFalse,
          reason: text,
        );
      }

      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a drive that was never synced still asks, rather than waits',
      (tester) async {
    // The other half of this slot, left exactly as it was: a decision the user
    // has to make reads as one, and must not be confused with a wait.
    await tester.binding.setSurfaceSize(phoneSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      host(
        DriveDetailUnsyncedCard(drive: drive(id: 'drive-1', name: 'Photos')),
      ),
    );
    await tester.pump();

    // The card's two 283x283 action tiles do not fit their own contents under
    // the test font's square glyphs. That predates this work, is not what this
    // test is about, and the card is left exactly as it was found.
    while (tester.takeException() != null) {}

    expect(find.text('Drive Not Synced'), findsOneWidget);
    expect(find.text('Sync Now'), findsOneWidget);

    // Nothing about it reads as work in progress.
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Syncing All Drives'), findsNothing);
    expect(find.textContaining('s elapsed'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('the bar does not rewind when the sync ends', (tester) async {
    // When the sync finishes, the subtitle, the phase line and the elapsed
    // counter all disappear at once and the Column's children shrink. An
    // unkeyed bar is then matched by POSITION against a different widget,
    // destroyed, and remounted at its mount-time seed - so a bar live at 99%
    // animates backwards. That is the backwards-moving bar the monotonic sink
    // underneath exists to prevent, reintroduced a layer up.
    selectDrive('Photos');
    await pumpSyncing(
      tester,
      reporting: SyncProgress.initial().copyWith(
        progress: 0.99,
        statusMessage: 'Updating transaction statuses...',
      ),
    );

    // Let the fill animation reach the value before reading it.
    await tester.pump(const Duration(milliseconds: 1200));
    expect(bar(tester).value, closeTo(0.99, 0.01));

    // The sync ends; the panel stays up while the folder opens.
    syncStates.add(SyncIdle());
    await tester.pump(const Duration(milliseconds: 10));

    final after = bar(tester).value;
    expect(
      after == null || after >= 0.99,
      isTrue,
      reason: 'the bar fell back to $after after reading 0.99',
    );

    await tester.pumpWidget(const SizedBox());
  });
}

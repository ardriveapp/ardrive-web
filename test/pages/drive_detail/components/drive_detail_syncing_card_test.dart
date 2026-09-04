import 'package:ardrive/components/progress_bar.dart';
import 'package:ardrive/sync/presentation/sync_loading_indicator.dart';
import 'dart:async';

import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
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
    // The plates, not a bar with nothing in it. One indicator per wait: two
    // was two things to read where there is one fact, and a bar that cannot
    // fill is the weaker of the pair.
    expect(find.byType(SyncLoadingIndicator), findsOneWidget);
    expect(find.byType(ProgressBar), findsNothing);
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
    expect(find.byType(SyncLoadingIndicator), findsOneWidget);
    expect(find.byType(ProgressBar), findsNothing);
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

    // No exception drain here. One used to sit on this widget, justified by
    // the action tiles not fitting their own contents - and it is exactly what
    // hid the card's buttons being laid out past its clip boundary at large
    // text scale, where a tap reached nothing at all. The tiles size to their
    // content now, so an overflow here is a real regression and must fail.
    expect(tester.takeException(), isNull);

    expect(find.text('Drive Not Synced'), findsOneWidget);
    expect(find.text('Sync Now'), findsOneWidget);

    // Nothing about it reads as work in progress.
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Syncing All Drives'), findsNothing);
    expect(find.textContaining('s elapsed'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  /// A sync that ran, finished and found nothing must not be drawn as a sync
  /// that never happened. Before this the card came back word for word -
  /// "Drive Not Synced", "Sync now to see your files and folders", the same
  /// Sync Now button - so pressing it read as a button that did nothing.
  group('the unsynced card after a sync that found nothing', () {
    /// How many layout overflows the card produces, drained so they do not
    /// leak into the next test. The two 283x283 action tiles do not fit their
    /// own contents under the test font's square glyphs; that predates this
    /// work, so what matters is that the new copy does not add to it.
    int overflowsRendering(WidgetTester tester) {
      var count = 0;
      while (tester.takeException() != null) {
        count++;
      }
      return count;
    }

    Future<int> pumpCard(
      WidgetTester tester, {
      required bool syncFoundNothing,
      Size size = phoneSize,
    }) async {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        host(
          DriveDetailUnsyncedCard(
            drive: drive(id: 'drive-1', name: 'Photos'),
            syncFoundNothing: syncFoundNothing,
          ),
          size: size,
        ),
      );
      await tester.pump();
      return overflowsRendering(tester);
    }

    testWidgets('says the sync looked and found nothing', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpCard(tester, syncFoundNothing: true);

      expect(find.text('Nothing Found Yet'), findsOneWidget);
      expect(
        find.textContaining('The sync finished, but nothing for this drive'),
        findsOneWidget,
      );

      // Not the card that was already acted on, and not the button that was
      // already pressed.
      expect(find.text('Drive Not Synced'), findsNothing);
      expect(find.text('Sync Now'), findsNothing);
      expect(find.text('Check Again'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('leaves the first-time card alone', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpCard(tester, syncFoundNothing: false);

      expect(find.text('Drive Not Synced'), findsOneWidget);
      expect(find.text('Sync Now'), findsOneWidget);
      expect(find.text('Nothing Found Yet'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('adds no overflow at 320px, on either wording', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final before = await pumpCard(tester, syncFoundNothing: false);
      await tester.pumpWidget(const SizedBox());
      final after = await pumpCard(tester, syncFoundNothing: true);
      await tester.pumpWidget(const SizedBox());

      // Absolute, not comparative. "No worse than before" was only ever a
      // defensible assertion while the tiles were a fixed square that
      // overflowed on its own; they size to their content now, so the honest
      // bar is zero - and a comparison against a non-zero baseline is how an
      // overflow stays invisible.
      expect(before, 0, reason: 'the card overflows a phone as it is');
      expect(after, 0,
          reason: 'the longer wording pushes the card off a phone');
    });

    testWidgets('reads the same on a desktop', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpCard(tester, syncFoundNothing: true, size: desktopSize);

      expect(find.text('Nothing Found Yet'), findsOneWidget);
      expect(find.text('Check Again'), findsOneWidget);
      expect(find.text('Drive Not Synced'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });
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

    // The sync ends; the panel stays up while the folder opens. The bar goes
    // with the sync rather than lingering: there is no longer a figure to
    // show, and a bar left on screen with nothing feeding it was reading a
    // stale 99% over "Opening Photos". It cannot rewind if it is not there.
    syncStates.add(SyncIdle());
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.byType(ProgressBar), findsNothing);
    expect(find.byType(SyncLoadingIndicator), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  group('when the drive list could not be read at all', () {
    late MockDriveDetailCubit driveDetailCubit;

    setUp(() {
      driveDetailCubit = MockDriveDetailCubit();
      whenListen(
        driveDetailCubit,
        const Stream<DriveDetailState>.empty(),
        initialState: DriveDetailDrivesUnavailable(),
      );
      when(() => driveDetailCubit.retryLoadingDrives())
          .thenAnswer((_) async {});
    });

    Widget unavailable({ArDriveThemeData? theme, Size size = phoneSize}) =>
        host(
          BlocProvider<DriveDetailCubit>.value(
            value: driveDetailCubit,
            child: const DriveDetailSyncingCard.driveListUnavailable(),
          ),
          theme: theme,
          size: size,
        );

    testWidgets('says what happened, and never that the user has no drives',
        (tester) async {
      await tester.binding.setSurfaceSize(phoneSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(unavailable());
      await tester.pump();

      expect(find.text('Your Drives Could Not Be Loaded'), findsOneWidget);
      expect(
        find.textContaining('Your drives are safe'),
        findsOneWidget,
      );

      // The three things the old screen did that this one may not: claim the
      // list is empty, offer a drive to create, and pretend work is still
      // going on.
      expect(find.textContaining('Getting Started'), findsNothing);
      expect(find.textContaining('Create new'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('offers a retry that actually runs one', (tester) async {
      await tester.binding.setSurfaceSize(phoneSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(unavailable());
      await tester.pump();

      await tester.tap(find.text('Try Again'));
      await tester.pump();

      verify(() => driveDetailCubit.retryLoadingDrives()).called(1);
    });

    testWidgets('fits a 320px phone and a wide desktop, in both themes',
        (tester) async {
      for (final theme in [
        lightTheme(),
        ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode()),
      ]) {
        for (final size in [phoneSize, desktopSize]) {
          await tester.binding.setSurfaceSize(size);
          await tester.pumpWidget(unavailable(theme: theme, size: size));
          await tester.pump();

          expect(find.text('Your Drives Could Not Be Loaded'), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(const SizedBox());
        }
      }

      await tester.binding.setSurfaceSize(null);
    });
  });
  testWidgets('reports what it has found rather than a fraction it cannot move',
      (tester) async {
    // The count accumulates per batch in the repository and used to be read
    // only at the end. A percentage needs a total the walk does not have until
    // it finishes; a count needs nothing, cannot stall, and is in the user's
    // own units.
    await pumpSyncing(
      tester,
      reporting: SyncProgress.initial().copyWith(
        progress: 0.02,
        entitiesSynced: 47,
      ),
    );

    expect(find.text('Found 47 items so far...'), findsOneWidget);
    expect(find.text('2% complete'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  group('the phase that can be counted', () {
    // The panel and the strip carry the same sentence for the same moment.
    // Every revision's metadata is one HTTP round trip, a few at a time, and
    // this is the only figure that moves while they are in flight.
    testWidgets('says how much of the fetch is behind it', (tester) async {
      await pumpSyncing(
        tester,
        reporting: SyncProgress.initial().copyWith(
          progress: 0.02,
          // The phase's own name, which is true and cannot move.
          statusMessage: 'Reading the drive history...',
          metadataFetchesCompleted: 340,
          metadataFetchesTotal: 2180,
        ),
      );

      expect(find.text('Reading 340 files...'), findsOneWidget);
      expect(find.text('Reading the drive history...'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('invents no total when there is no fetch to report',
        (tester) async {
      await pumpSyncing(
        tester,
        reporting: SyncProgress.initial().copyWith(
          statusMessage: 'Creating ghost folders...',
        ),
      );

      expect(find.textContaining('Reading'), findsNothing);
      expect(find.text('Creating ghost folders...'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    for (final theme in [
      ('light', lightTheme()),
      ('dark', ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode())),
    ]) {
      testWidgets('fits a 320px phone at text scale 2.0 in ${theme.$1}',
          (tester) async {
        tester.view.physicalSize = phoneSize;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await pumpSyncing(
          tester,
          theme: theme.$2,
          reporting: SyncProgress.initial().copyWith(
            progress: 0.02,
            // Five figures on both sides: the widest this line gets for a
            // real drive.
            metadataFetchesCompleted: 12345,
            metadataFetchesTotal: 12345,
          ),
        );
        await tester.pump(const Duration(milliseconds: 1100));

        expect(tester.takeException(), isNull);
        final finder = find.text('Reading 12,345 files...');
        expect(finder, findsOneWidget);
        expect(tester.getTopLeft(finder).dx, greaterThanOrEqualTo(0));
        expect(tester.getBottomRight(finder).dx, lessThanOrEqualTo(320.0));
        expect(
          tester.renderObject<RenderParagraph>(finder).didExceedMaxLines,
          isFalse,
        );

        await tester.pumpWidget(const SizedBox());
      });
    }
  });

  testWidgets('falls back to the percentage before anything has been found',
      (tester) async {
    await pumpSyncing(
      tester,
      reporting: SyncProgress.initial().copyWith(progress: 0.42),
    );

    expect(find.text('42% complete'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('does not promise a drive will open on another drive\'s sync',
      (tester) async {
    // A single-drive sync of a different drive finishes without touching this
    // one, so "Photos will open when the sync finishes" is a promise the
    // running sync cannot keep - and it counts the other drive's items while
    // it makes it.
    selectDrive('Photos');
    when(() => syncCubit.syncingDriveId).thenReturn('some-other-drive');

    await pumpSyncing(
      tester,
      reporting: SyncProgress.initial().copyWith(
        progress: 0.4,
        isSingleDriveSync: true,
      ),
    );

    expect(find.text('Photos will open when the sync finishes'), findsNothing);
    expect(
      find.text('Another drive is syncing. This one opens once you sync it.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
  });
}

import 'dart:async';

import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../test_utils/mocks.dart';

class _MockDriveDetailCubit extends MockCubit<DriveDetailState>
    implements DriveDetailCubit {}

/// The card a never-synced drive opens on, and its two Sync buttons.
///
/// `SyncCubit` refuses a second sync outright now - one at a time, no queue -
/// and `syncCurrentDrive` reads the result of the sync it thought it started,
/// so a press that was refused comes back and reports that the sync found
/// nothing. The buttons have to say they are unavailable rather than take a
/// press that turns into a false report.
void main() {
  late MockSyncBloc syncCubit;
  late _MockDriveDetailCubit driveDetailCubit;
  late StreamController<SyncState> syncStates;

  setUp(() {
    syncCubit = MockSyncBloc();
    driveDetailCubit = _MockDriveDetailCubit();
    syncStates = StreamController<SyncState>.broadcast();

    whenListen(syncCubit, syncStates.stream, initialState: SyncIdle());
    whenListen(
      driveDetailCubit,
      const Stream<DriveDetailState>.empty(),
      initialState: DriveDetailLoadInProgress(),
    );

    when(() => driveDetailCubit.syncCurrentDrive()).thenAnswer((_) async {});
    when(() => driveDetailCubit.syncAllAndRefreshCurrentDrive())
        .thenAnswer((_) async {});
  });

  tearDown(() async {
    await syncStates.close();
  });

  Drive drive() => Drive(
        id: 'drive-a',
        rootFolderId: 'drive-a-root',
        ownerAddress: 'owner',
        name: 'Photos',
        privacy: 'public',
        isHidden: false,
        dateCreated: DateTime(2026, 3, 4),
        lastUpdated: DateTime(2026, 3, 4),
      );

  /// No `FlutterError.onError` filter, deliberately.
  ///
  /// This helper used to install one that dropped "A RenderFlex overflowed",
  /// on the grounds that the card's two fixed 283x283 tiles ran a few pixels
  /// past themselves under the test font. That filter is why nothing here ever
  /// failed while the tiles were clipping their own buttons away: [ArDriveCard]
  /// clips, so from about 1.3x the buttons were laid out past the boundary,
  /// drawn nowhere and hit by nothing, and the only signal was the overflow
  /// this swallowed. An overflow in this card is a defect in this card.
  Future<void> pumpCard(
    WidgetTester tester, {
    required bool isSyncing,
    String? syncingDriveId,
    bool syncFoundNothing = false,
    double textScale = 1,
    Size surface = const Size(390, 1600),
  }) async {
    when(() => syncCubit.state)
        .thenReturn(isSyncing ? SyncInProgress() : SyncIdle());
    when(() => syncCubit.syncingDriveId).thenReturn(syncingDriveId);

    // `setSurfaceSize` does NOT change what `MediaQuery` reports, and
    // `ScreenTypeLayout` picks its branch from `MediaQuery.size` - so sizing
    // this way alone left every case, including the ones named "on a desktop
    // window", rendering the mobile branch. This trap has produced a
    // false-green three times in this feature; set the view itself.
    tester.view.physicalSize = surface * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: Scaffold(
                body: MultiBlocProvider(
                  providers: [
                    BlocProvider<SyncCubit>.value(value: syncCubit),
                    BlocProvider<DriveDetailCubit>.value(
                      value: driveDetailCubit,
                    ),
                  ],
                  child: DriveDetailUnsyncedCard(
                    drive: drive(),
                    syncFoundNothing: syncFoundNothing,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  ArDriveButtonNew buttonNamed(WidgetTester tester, String name) =>
      tester.widget<ArDriveButtonNew>(
        find.widgetWithText(ArDriveButtonNew, name),
      );

  testWidgets('both offers are live when nothing is running', (tester) async {
    await pumpCard(tester, isSyncing: false);

    expect(buttonNamed(tester, 'Sync Now').isDisabled, isFalse);
    expect(buttonNamed(tester, 'Sync Now').onPressed, isNotNull);
    expect(buttonNamed(tester, 'Sync All Drives').isDisabled, isFalse);
  });

  testWidgets('both say they are unavailable while a sync runs',
      (tester) async {
    await pumpCard(tester, isSyncing: true);

    // `isDisabled` as well as a null callback: ArDriveButtonNew picks its
    // colours off the flag alone, so without it the button looks live and
    // does nothing.
    expect(buttonNamed(tester, 'Sync Now').isDisabled, isTrue);
    expect(buttonNamed(tester, 'Sync Now').onPressed, isNull);
    expect(buttonNamed(tester, 'Sync All Drives').isDisabled, isTrue);
    expect(buttonNamed(tester, 'Sync All Drives').onPressed, isNull);
  });

  group('the kebab offers the same answer as the buttons', () {
    // The menu is mounted twice - the desktop header and the phone header -
    // and it is one widget, so a fix cannot land on one copy and miss the
    // other. Both used to take the press and hand it to `syncCurrentDrive`,
    // which came back from the refusal and reported that the sync had looked
    // and found nothing.
    Future<void> pumpMenu(WidgetTester tester) => tester.pumpWidget(
          ArDriveTheme(
            themeData: lightTheme(),
            child: MaterialApp(
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('en', '')],
              home: Portal(
                child: Scaffold(
                  body: MultiBlocProvider(
                    providers: [
                      BlocProvider<SyncCubit>.value(value: syncCubit),
                      BlocProvider<DriveDetailCubit>.value(
                        value: driveDetailCubit,
                      ),
                    ],
                    child: UnsyncedDriveMenu(
                      drive: drive(),
                      isOwner: true,
                      child: ArDriveIcons.kebabMenu(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

    ArDriveDropdownItem syncItem(WidgetTester tester) {
      final menu = tester.widget<ArDriveDropdown>(
        find.byType(ArDriveDropdown),
      );

      return menu.items.first;
    }

    testWidgets('live when nothing is running', (tester) async {
      when(() => syncCubit.state).thenReturn(SyncIdle());

      await pumpMenu(tester);
      await tester.pump();

      final item = syncItem(tester);

      expect((item.content as ArDriveDropdownItemTile).name, 'Sync This Drive');
      expect(item.onClick, isNotNull);
      expect((item.content as ArDriveDropdownItemTile).isDisabled, isFalse);
    });

    testWidgets('unavailable while a sync runs', (tester) async {
      when(() => syncCubit.state).thenReturn(SyncInProgress());

      await pumpMenu(tester);
      await tester.pump();

      final item = syncItem(tester);

      expect(item.onClick, isNull);
      expect((item.content as ArDriveDropdownItemTile).isDisabled, isTrue,
          reason: 'the tile picks its colours off the flag alone, so a null '
              'callback on its own leaves an item that looks live and does '
              'nothing');
    });

    testWidgets('and it notices a sync starting under it', (tester) async {
      // It watches the cubit rather than reading it once, so a menu built
      // before a sync started is not left offering an action that is now
      // refused.
      when(() => syncCubit.state).thenReturn(SyncIdle());

      await pumpMenu(tester);
      await tester.pump();

      expect(syncItem(tester).onClick, isNotNull);

      when(() => syncCubit.state).thenReturn(SyncInProgress());
      syncStates.add(SyncInProgress());
      await tester.pump(const Duration(milliseconds: 10));

      expect(syncItem(tester).onClick, isNull);
    });
  });

  group('a drive that was never started says so', () {
    // One sync at a time and no queue: opening a never-walked drive while a
    // different one is syncing starts no request at all. Left unsaid, that is
    // an unsynced card with two unavailable buttons, nothing in flight, and a
    // strip at the top of the app reporting a sync that is not this one.
    const notStarted =
        'Another drive is syncing, so this one was not started. Sync it once '
        'that one finishes.';
    const alreadyRunning = 'A sync is already running for this drive.';

    testWidgets('nothing is claimed when no sync is running', (tester) async {
      await pumpCard(tester, isSyncing: false);

      expect(find.text(notStarted), findsNothing);
      expect(find.text(alreadyRunning), findsNothing);
    });

    testWidgets('another drive syncing is named as the reason', (tester) async {
      await pumpCard(tester, isSyncing: true, syncingDriveId: 'drive-b');

      expect(find.text(notStarted), findsOneWidget);
      expect(find.text(alreadyRunning), findsNothing);
    });

    testWidgets("this drive's own sync is not called someone else's",
        (tester) async {
      await pumpCard(tester, isSyncing: true, syncingDriveId: 'drive-a');

      expect(find.text(alreadyRunning), findsOneWidget);
      expect(find.text(notStarted), findsNothing);
    });

    testWidgets('and a sync of every drive covers this one', (tester) async {
      // A null drive id is an all-drives sync, which is fetching this drive
      // too - so it is not "not started".
      await pumpCard(tester, isSyncing: true);

      expect(find.text(alreadyRunning), findsOneWidget);
      expect(find.text(notStarted), findsNothing);
    });
  });

  group('the offers survive the reader\'s text scale', () {
    // The tiles were `ArDriveCard(width: 283, height: 283)` with 31px of
    // padding around a column of text that grows with the text scale, and
    // `ArDriveCard` clips. Nothing overflowed *visibly*: from about 1.3x the
    // buttons were simply laid out below the clip boundary, so they were
    // painted nowhere and hit by nothing. At 2.0 a press on "Sync Now" reached
    // no callback at all - a button that is present, correctly labelled,
    // correctly coloured and inert.
    //
    // The test presses them, rather than looking at them, for that reason.
    for (final scale in [1.0, 1.3, 1.6, 2.0]) {
      for (final layout in {
        'a phone': const Size(390, 1600),
        'a desktop window': const Size(1200, 900),
      }.entries) {
        testWidgets('Sync Now can be pressed at ${scale}x on ${layout.key}',
            (tester) async {
          await pumpCard(
            tester,
            isSyncing: false,
            textScale: scale,
            surface: layout.value,
          );

          final button = find.widgetWithText(ArDriveButtonNew, 'Sync Now');
          expect(button, findsOneWidget);

          // Scrolled to, not assumed on screen: the card is allowed to be
          // taller than the window at a large text scale - that is what the
          // scroll view is for - but the button has to be reachable.
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();

          // No `warnIfMissed: false`: a tap that lands on nothing is exactly
          // the defect, and it has to fail here rather than warn.
          await tester.tap(button);
          await tester.pump();

          verify(() => driveDetailCubit.syncCurrentDrive()).called(1);
        });

        testWidgets(
            'Sync All Drives can be pressed at ${scale}x on ${layout.key}',
            (tester) async {
          await pumpCard(
            tester,
            isSyncing: false,
            textScale: scale,
            surface: layout.value,
          );

          final button =
              find.widgetWithText(ArDriveButtonNew, 'Sync All Drives');
          expect(button, findsOneWidget);

          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          await tester.tap(button);
          await tester.pump();

          verify(() => driveDetailCubit.syncAllAndRefreshCurrentDrive())
              .called(1);
        });
      }
    }

    testWidgets('and the card that says a sync already looked does too',
        (tester) async {
      // The same tiles, with the longer "Check Again" copy in them.
      await pumpCard(
        tester,
        isSyncing: false,
        syncFoundNothing: true,
        textScale: 2.0,
      );

      final button = find.widgetWithText(ArDriveButtonNew, 'Check Again');
      expect(button, findsOneWidget);

      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pump();

      verify(() => driveDetailCubit.syncCurrentDrive()).called(1);
    });
  });
}

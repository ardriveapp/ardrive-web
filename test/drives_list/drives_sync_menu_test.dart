import 'dart:async';
import 'dart:io';

import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/drives_list/presentation/drives_sync_menu.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../test_utils/mocks.dart';

class _MockProfileNameBloc extends MockBloc<ProfileNameEvent, ProfileNameState>
    implements ProfileNameBloc {}

/// The drive-wide sync actions, on the page about drives.
///
/// They used to sit behind the top bar's indicator, which was present on every
/// screen whether or not anything was happening. That indicator now appears
/// only when there is something to report, so the controls moved to the surface
/// that is always there and that lists the drives they act on.
void main() {
  late MockSyncBloc syncCubit;
  late MockDrivesCubit drivesCubit;
  late _MockProfileNameBloc profileNameBloc;
  late StreamController<SyncState> states;

  Drive drive(String id, {int lastBlockHeight = 0}) => Drive(
        id: id,
        rootFolderId: '$id-root',
        ownerAddress: 'me',
        name: id,
        privacy: 'public',
        isHidden: false,
        dateCreated: DateTime(2026, 1, 1),
        lastUpdated: DateTime(2026, 1, 1),
        lastBlockHeight: lastBlockHeight,
      );

  void withDrives(List<Drive> drives) {
    whenListen(
      drivesCubit,
      const Stream<DrivesState>.empty(),
      initialState: DrivesLoadSuccess(
        selectedDriveId: null,
        userDrives: drives,
        sharedDrives: const [],
        drivesWithAlerts: const [],
        canCreateNewDrive: true,
      ),
    );
  }

  setUpAll(() => registerFallbackValue(SyncTrigger.background));

  setUp(() {
    syncCubit = MockSyncBloc();
    drivesCubit = MockDrivesCubit();
    profileNameBloc = _MockProfileNameBloc();
    states = StreamController<SyncState>.broadcast();

    whenListen(syncCubit, states.stream, initialState: SyncIdle());
    when(() => syncCubit.syncProgress).thenReturn(SyncProgress.initial());
    when(() => syncCubit.clearErrorState()).thenReturn(null);
    when(() => syncCubit.retryFailedDrives(any())).thenAnswer((_) async {});
    when(() => syncCubit.startSync(
          deepSync: any(named: 'deepSync'),
          skipTabVisibilityCheck: any(named: 'skipTabVisibilityCheck'),
          onlyDriveIds: any(named: 'onlyDriveIds'),
          trigger: any(named: 'trigger'),
        )).thenAnswer((_) async => true);

    withDrives([drive('walked', lastBlockHeight: 12)]);
  });

  tearDown(() async => states.close());

  Widget host({double textScale = 1}) => Portal(
        child: ArDriveTheme(
          themeData: lightTheme(),
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en', '')],
            // The full resync confirmation is a dialog, and the app's
            // dialogs report themselves to the activity tracker.
            home: ChangeNotifierProvider<ActivityTracker>(
              create: (_) => ActivityTracker(),
              child: Scaffold(
                body: MultiBlocProvider(
                  providers: [
                    BlocProvider<SyncCubit>.value(value: syncCubit),
                    BlocProvider<DrivesCubit>.value(value: drivesCubit),
                    BlocProvider<ProfileNameBloc>.value(value: profileNameBloc),
                  ],
                  child: const Align(
                    alignment: Alignment.topRight,
                    child: DrivesSyncMenu(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> openMenu(WidgetTester tester, {double textScale = 1}) async {
    await tester.pumpWidget(host(textScale: textScale));
    await tester.pump();
    await tester.tap(find.byType(DrivesSyncMenu));
    await tester.pump(const Duration(milliseconds: 300));
  }

  ArDriveDropdownItemTile itemNamed(WidgetTester tester, String name) =>
      tester.widget<ArDriveDropdownItemTile>(
        find.widgetWithText(ArDriveDropdownItemTile, name),
      );

  ArDriveDropdownItem entryNamed(WidgetTester tester, String name) =>
      tester.widget<ArDriveDropdownItem>(
        find.ancestor(
          of: find.widgetWithText(ArDriveDropdownItemTile, name),
          matching: find.byType(ArDriveDropdownItem),
        ),
      );

  /// It is drawn by hand so the menu can open, which once left it with none
  /// of a button's states: it read as a label. It now takes the outline
  /// button's own tokens, so these compare against the theme rather than
  /// against hex values that would go stale.
  group('answers a pointer like an outline button', () {
    BoxDecoration face(WidgetTester tester) => tester
        .widgetList<Container>(find.descendant(
          of: find.byType(DrivesSyncMenu),
          matching: find.byType(Container),
        ))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.border != null);

    Color borderOf(BoxDecoration d) => (d.border! as Border).top.color;

    late ArDriveColorTokens tokens;

    Future<TestGesture> hover(WidgetTester tester) async {
      await tester.pumpWidget(host());
      await tester.pump();
      tokens = lightTheme().colorTokens;

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(DrivesSyncMenu)));
      await tester.pump();
      return mouse;
    }

    testWidgets('resting', (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();
      tokens = lightTheme().colorTokens;

      expect(face(tester).color, tokens.buttonOutlineDefault);
      expect(borderOf(face(tester)), tokens.strokeMid);
    });

    testWidgets('under a pointer', (tester) async {
      await hover(tester);

      expect(face(tester).color, tokens.buttonOutlineHover);
      expect(borderOf(face(tester)), tokens.strokeHigh);
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
      );
    });

    testWidgets('and pressed', (tester) async {
      final mouse = await hover(tester);

      await mouse.down(tester.getCenter(find.byType(DrivesSyncMenu)));
      await tester.pump();

      expect(face(tester).color, tokens.buttonOutlinePress);

      await mouse.up();
      await tester.pump(const Duration(milliseconds: 300));
    });

    /// The reason it is not a real button: that would swallow this tap.
    testWidgets('and still opens its menu when clicked', (tester) async {
      final mouse = await hover(tester);

      await mouse.down(tester.getCenter(find.byType(DrivesSyncMenu)));
      await mouse.up();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Sync history'), findsOneWidget);
    });

    testWidgets('and lets go when the pointer leaves', (tester) async {
      final mouse = await hover(tester);

      await mouse.moveTo(const Offset(1, 1));
      await tester.pump();

      expect(face(tester).color, tokens.buttonOutlineDefault);
      expect(borderOf(face(tester)), tokens.strokeMid);
    });
  });

  group('what it offers', () {
    testWidgets('every drive-wide action, in one place', (tester) async {
      await openMenu(tester);

      expect(find.text('Sync all drives'), findsOneWidget);
      expect(find.text('Full resync all drives'), findsOneWidget);
      expect(find.text('Sync history'), findsOneWidget);
    });

    testWidgets('names syncing everything one way, synced before or not',
        (tester) async {
      // One name for one action. The menu used to say "Resync" after a first
      // sync and "Sync All Drives" before one, beside a banner and a card that
      // said "Sync All Drives" too.
      withDrives([drive('never-walked')]);

      await openMenu(tester);

      expect(find.text('Sync all drives'), findsOneWidget);
    });

    testWidgets('and the button reads "Sync" before anything has synced',
        (tester) async {
      // The page's own banner says "Sync all drives" then; the same words
      // on this button put the action on the page twice.
      withDrives([drive('never-walked')]);

      await tester.pumpWidget(host());
      await tester.pump();

      expect(find.text('Sync'), findsOneWidget);
      expect(find.text('Sync all drives'), findsNothing);
    });
  });

  group('while a sync runs', () {
    setUp(() => when(() => syncCubit.state)
        .thenReturn(SyncInProgress(trigger: SyncTrigger.userInitiated)));

    testWidgets('the actions are disabled rather than silently dropped',
        (tester) async {
      // `startSync` returns immediately while one is running, so an item that
      // looks live, closes the menu and drops the request is a lie.
      whenListen(syncCubit, states.stream,
          initialState: SyncInProgress(trigger: SyncTrigger.userInitiated));

      await openMenu(tester);

      expect(itemNamed(tester, 'Sync all drives').isDisabled, isTrue);
      expect(itemNamed(tester, 'Full resync all drives').isDisabled, isTrue);
      expect(entryNamed(tester, 'Sync all drives').onClick, isNull);
    });

    testWidgets('but the record stays reachable', (tester) async {
      // Reading what past syncs did is not an action on this one, and is most
      // wanted while a slow sync is running.
      whenListen(syncCubit, states.stream,
          initialState: SyncInProgress(trigger: SyncTrigger.userInitiated));

      await openMenu(tester);

      expect(entryNamed(tester, 'Sync history').onClick, isNotNull);
    });
  });

  group('after a sync that lost drives', () {
    testWidgets('it offers to retry exactly those drives', (tester) async {
      whenListen(
        syncCubit,
        states.stream,
        initialState: SyncCompleteWithErrors(
          failedDrives: 2,
          totalDrives: 5,
          failedDriveIds: const ['drive-a', 'drive-b'],
          errorMessages: const {},
          skippedEntityCount: 0,
          skippedEntityTxIdsByDrive: const {},
          trigger: SyncTrigger.userInitiated,
          completedAt: DateTime.now(),
        ),
      );

      await openMenu(tester);
      expect(find.text('Retry failed'), findsOneWidget);

      entryNamed(tester, 'Retry failed').onClick!();
      await tester.pump();

      verify(() => syncCubit.retryFailedDrives(['drive-a', 'drive-b']))
          .called(1);
    });

    testWidgets('and does not offer it when nothing failed', (tester) async {
      await openMenu(tester);

      expect(find.text('Retry failed'), findsNothing);
    });
  });

  // "Deep resync" said nothing about what it did differently, and the drive
  // menus called the same thing "Deep sync". Both sync items now say what
  // they do, and the slow one asks first.
  group('full resync', () {
    // The real face, so the descriptions are measured as a user sees them:
    // the test font's glyphs are a square em each, several times wider. Loaded
    // here because a real file read never completes inside `testWidgets`.
    setUpAll(() async {
      final bytes = await File(
        'packages/ardrive_ui/assets/fonts/Wavehaus-66Book.otf',
      ).readAsBytes();
      await (FontLoader('packages/ardrive_ui/Wavehaus')
            ..addFont(
              Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
            ))
          .load();
    });

    // Pressed through the button, as the items are through `onClick`: the
    // still-open menu's portal sits above the dialog in this harness and
    // takes the tap. In the app, choosing the item closes the menu.
    void pressButton(WidgetTester tester, String title) => tester
        .widget<ArDriveButtonNew>(find.widgetWithText(ArDriveButtonNew, title))
        .onPressed!();

    testWidgets('both sync items say what they do, in full', (tester) async {
      await openMenu(tester);

      for (final description in [
        'Gets changes since the last sync.',
        'Rereads all history. Slower; use it if something looks missing.',
      ]) {
        expect(find.text(description), findsOneWidget);
        // At the default text size the sentence fits its two lines rather
        // than ending in an ellipsis.
        final paragraph =
            tester.renderObject<RenderParagraph>(find.text(description));
        expect(paragraph.didExceedMaxLines, isFalse, reason: description);
      }
    });

    testWidgets('asks first, and Cancel starts nothing', (tester) async {
      await openMenu(tester);

      entryNamed(tester, 'Full resync all drives').onClick!();
      await tester.pumpAndSettle();

      expect(
        find.textContaining('rereads the entire history of all your drives'),
        findsOneWidget,
      );
      expect(find.textContaining('Nothing on this device is deleted'),
          findsOneWidget);

      pressButton(tester, 'Cancel');
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing on this device is deleted'),
          findsNothing);
      verifyNever(() => syncCubit.startSync(
            deepSync: any(named: 'deepSync'),
            skipTabVisibilityCheck: any(named: 'skipTabVisibilityCheck'),
            onlyDriveIds: any(named: 'onlyDriveIds'),
            trigger: any(named: 'trigger'),
          ));
    });

    testWidgets('and confirming starts it', (tester) async {
      await openMenu(tester);

      entryNamed(tester, 'Full resync all drives').onClick!();
      await tester.pumpAndSettle();
      pressButton(tester, 'Full resync');
      await tester.pumpAndSettle();

      verify(() => syncCubit.startSync(
            deepSync: true,
            skipTabVisibilityCheck: any(named: 'skipTabVisibilityCheck'),
            onlyDriveIds: any(named: 'onlyDriveIds'),
            trigger: any(named: 'trigger'),
          )).called(1);
    });

    // The menu sizes itself from a height it is given, not from its items, so
    // taller items must not push the last one out of reach.
    testWidgets('the menu still fits a 320px phone at text scale 2.0',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await openMenu(tester, textScale: 2);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Inside the menu's box, not below its edge where nothing scrolls to it.
      final menu = tester.getRect(find
          .ancestor(
              of: find.text('Sync history'), matching: find.byType(ArDriveCard))
          .first);
      final last = tester.getRect(
          find.widgetWithText(ArDriveDropdownItemTile, 'Sync history'));
      // Within the card's border: the dropdown draws its 1px border inside
      // the height it is given, in every menu, so the last row gives up a
      // pixel of its bottom padding, never its text.
      expect(last.bottom, lessThanOrEqualTo(menu.bottom + 2));
    });
  });
}

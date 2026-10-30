import 'dart:async';
import 'dart:io';

import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/drives_list/domain/drive_list_item.dart';
import 'package:ardrive/drives_list/presentation/drives_list_cubit.dart';
import 'package:ardrive/drives_list/presentation/drives_list_page.dart';
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

class _MockDrivesListCubit extends MockCubit<DrivesListState>
    implements DrivesListCubit {}

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

  Widget host({
    double textScale = 1,
    DrivesListCubit? drivesList,
    Widget? child,
  }) =>
      Portal(
        child: ArDriveTheme(
          themeData: lightTheme(),
          // Above the navigator, where the app provides them: the menu opens
          // in the navigator's overlay and reads them from there.
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<ActivityTracker>(
                create: (_) => ActivityTracker(),
              ),
              BlocProvider<SyncCubit>.value(value: syncCubit),
              BlocProvider<DrivesCubit>.value(value: drivesCubit),
              BlocProvider<ProfileNameBloc>.value(value: profileNameBloc),
              if (drivesList != null)
                BlocProvider<DrivesListCubit>.value(value: drivesList),
            ],
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
              home: Scaffold(
                body: child ??
                    const Align(
                      alignment: Alignment.topRight,
                      child: DrivesSyncMenu(),
                    ),
              ),
            ),
          ),
        ),
      );

  Future<void> openMenu(WidgetTester tester, {double textScale = 1}) async {
    await tester.pumpWidget(host(textScale: textScale));
    await tester.pump();
    await tester.tap(find.byKey(DrivesSyncMenu.moreKey));
    // The menu enters the navigator's overlay on the frame after the tap.
    await tester.pump();
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
    /// A half's fill.
    BoxDecoration face(WidgetTester tester, Key half) => tester
        .widgetList<Container>(find.descendant(
          of: find.byKey(half),
          matching: find.byType(Container),
        ))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .first;

    /// The one outline around both halves.
    Color outline(WidgetTester tester) => (tester
            .widgetList<Container>(find.descendant(
              of: find.byType(DrivesSyncMenu),
              matching: find.byType(Container),
            ))
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .firstWhere((d) => d.border != null)
            .border! as Border)
        .top
        .color;

    late ArDriveColorTokens tokens;

    /// The colours change over a short animation, which starts on the frame
    /// after the pointer moves.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<TestGesture> hover(WidgetTester tester, Key half) async {
      await tester.pumpWidget(host());
      await tester.pump();
      tokens = lightTheme().colorTokens;

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byKey(half)));
      await settle(tester);
      return mouse;
    }

    for (final (name, half) in [
      ('the main half', DrivesSyncMenu.primaryKey),
      ('the chevron', DrivesSyncMenu.moreKey),
    ]) {
      group(name, () {
        testWidgets('resting', (tester) async {
          await tester.pumpWidget(host());
          await tester.pump();
          tokens = lightTheme().colorTokens;

          expect(face(tester, half).color, tokens.buttonOutlineDefault);
          expect(outline(tester), tokens.strokeMid);
        });

        testWidgets('under a pointer', (tester) async {
          await hover(tester, half);

          expect(face(tester, half).color, tokens.buttonOutlineHover);
          expect(outline(tester), tokens.strokeHigh);
          expect(
            RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
            SystemMouseCursors.click,
          );
        });

        testWidgets('and pressed', (tester) async {
          final mouse = await hover(tester, half);

          await mouse.down(tester.getCenter(find.byKey(half)));
          await settle(tester);

          expect(face(tester, half).color, tokens.buttonOutlinePress);

          await mouse.up();
          await settle(tester);
        });

        testWidgets('and lets go when the pointer leaves', (tester) async {
          final mouse = await hover(tester, half);

          await mouse.moveTo(const Offset(1, 1));
          await settle(tester);

          expect(face(tester, half).color, tokens.buttonOutlineDefault);
          expect(outline(tester), tokens.strokeMid);
        });
      });
    }

    /// The reason the chevron is not a real button: that would swallow this
    /// tap.
    testWidgets('the chevron still opens the menu when clicked',
        (tester) async {
      final mouse = await hover(tester, DrivesSyncMenu.moreKey);

      await mouse.down(tester.getCenter(find.byKey(DrivesSyncMenu.moreKey)));
      await mouse.up();
      await settle(tester);

      expect(find.text('Sync history'), findsOneWidget);
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
  });

  /// The main half does the one obvious thing for the page as it stands. It is
  /// the page's only sync button, and never red: the sidebar's New is the
  /// view's one primary.
  group('the main half', () {
    late _MockDrivesListCubit drivesList;

    DriveListItem item(String id, {required bool walked}) => DriveListItem(
          id: id,
          name: id,
          isPrivate: false,
          isSharedWithMe: false,
          isHidden: false,
          dateCreated: DateTime(2026, 1, 1),
          hasBeenWalked: walked,
          fileCount: walked ? 1 : null,
          totalSize: walked ? 1 : null,
          lastSyncedAt: walked ? DateTime(2026, 1, 1) : null,
          isSyncing: false,
          lastSyncFailed: false,
        );

    void listed({required bool walked, Set<String> selected = const {}}) {
      whenListen(
        drivesList,
        const Stream<DrivesListState>.empty(),
        initialState: DrivesListLoaded(
          drives: [item('a', walked: walked), item('b', walked: walked)],
          selected: selected,
        ),
      );
      when(() => drivesList.selectionCount).thenReturn(selected.length);
    }

    Text label(WidgetTester tester) => tester.widget<Text>(find.descendant(
          of: find.byKey(DrivesSyncMenu.primaryKey),
          matching: find.byType(Text),
        ));

    Color fillOf(WidgetTester tester) => tester
        .widgetList<Container>(find.descendant(
          of: find.byKey(DrivesSyncMenu.primaryKey),
          matching: find.byType(Container),
        ))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .first
        .color!;

    setUp(() {
      drivesList = _MockDrivesListCubit();
      when(() => drivesList.syncSelectedDrives(deep: any(named: 'deep')))
          .thenReturn(null);
      when(() => syncCubit.cancelSync()).thenReturn(null);
    });

    Future<void> pumpMenu(WidgetTester tester) async {
      await tester.pumpWidget(host(drivesList: drivesList));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('reads "Sync" and is outlined once drives have synced',
        (tester) async {
      listed(walked: true);
      await pumpMenu(tester);

      expect(label(tester).data, 'Sync');
      // The label style every button uses: paragraphLarge SemiBold.
      final style = label(tester).style!;
      final buttonLabel = ArDriveTypographyNew.of(
        tester.element(find.byKey(DrivesSyncMenu.primaryKey)),
      ).paragraphLarge(fontWeight: ArFontWeight.semiBold);
      expect(style.fontSize, buttonLabel.fontSize);
      expect(style.fontWeight, buttonLabel.fontWeight);
      expect(fillOf(tester), lightTheme().colorTokens.buttonOutlineDefault);
    });

    testWidgets('reads "Sync all drives", outlined, before anything has synced',
        (tester) async {
      listed(walked: false);
      await pumpMenu(tester);

      expect(label(tester).data, 'Sync all drives');
      // Never red: the sidebar's New is the view's one primary.
      expect(fillOf(tester), lightTheme().colorTokens.buttonOutlineDefault);

      await tester.tap(find.byKey(DrivesSyncMenu.primaryKey));
      await tester.pump();

      verify(() => drivesList.syncSelectedDrives(deep: false)).called(1);
      expect(find.text('Sync history'), findsNothing,
          reason: 'the main half acts; only the chevron opens the menu');
    });

    testWidgets('reads "Sync 2 selected", outlined, with two drives ticked',
        (tester) async {
      listed(walked: true, selected: const {'a', 'b'});
      await pumpMenu(tester);

      expect(label(tester).data, 'Sync 2 selected');
      expect(fillOf(tester), lightTheme().colorTokens.buttonOutlineDefault);

      await tester.tap(find.byKey(DrivesSyncMenu.primaryKey));
      await tester.pump();

      verify(() => drivesList.syncSelectedDrives(deep: false)).called(1);
    });

    testWidgets('offers to stop a sync that can be stopped', (tester) async {
      listed(walked: false);
      whenListen(syncCubit, states.stream,
          initialState: SyncInProgress(trigger: SyncTrigger.userInitiated));
      await pumpMenu(tester);

      expect(label(tester).data, 'Stop syncing');
      expect(fillOf(tester), lightTheme().colorTokens.buttonOutlineDefault,
          reason: 'stopping is not the action to draw the eye to');

      await tester.tap(find.byKey(DrivesSyncMenu.primaryKey));
      await tester.pump();

      verify(() => syncCubit.cancelSync()).called(1);
      verifyNever(() => drivesList.syncSelectedDrives(deep: false));
    });

    testWidgets('and is unavailable while the drive list refreshes',
        (tester) async {
      // `cancelSync` does nothing then - the refresh holds no token - so a
      // "Stop syncing" here would acknowledge a press and change nothing.
      listed(walked: true);
      whenListen(syncCubit, states.stream, initialState: SyncLoadingDrives());
      await pumpMenu(tester);

      expect(label(tester).data, 'Sync');
      // Drawn as a disabled button is: the disabled fill and the faintest
      // text, not an outline with a dimmed label.
      expect(fillOf(tester), lightTheme().colorTokens.buttonDisabled);
      expect(label(tester).style?.color, lightTheme().colorTokens.textXLow);

      await tester.tap(find.byKey(DrivesSyncMenu.primaryKey));
      await tester.pump();

      verifyNever(() => syncCubit.cancelSync());
      verifyNever(() => drivesList.syncSelectedDrives(deep: false));
    });

    testWidgets('without the drives list it syncs every drive', (tester) async {
      await tester.pumpWidget(host());
      await tester.pump(const Duration(milliseconds: 300));

      expect(label(tester).data, 'Sync');

      await tester.tap(find.byKey(DrivesSyncMenu.primaryKey));
      await tester.pump();

      verify(() => syncCubit.startSync(
            deepSync: false,
            skipTabVisibilityCheck: any(named: 'skipTabVisibilityCheck'),
            onlyDriveIds: any(named: 'onlyDriveIds'),
            trigger: any(named: 'trigger'),
          )).called(1);
    });

    /// Where the page actually puts it: at the end of the heading row, beside
    /// a title that takes the rest. A row hands a child that is not flexible
    /// unlimited width, and the main half's label is flexible so it can be
    /// cut short - which needs a bounded width to be cut short within.
    for (final (width, scale) in [(1280.0, 1.0), (320.0, 2.0)]) {
      testWidgets(
          'sits in the page heading at ${width.toInt()}px and text scale '
          '$scale', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        listed(walked: false);

        await tester.pumpWidget(host(
          drivesList: drivesList,
          textScale: scale,
          child: DrivesListBody(
            state: DrivesListLoaded(
              drives: [item('a', walked: false), item('b', walked: false)],
            ),
            onOpenDrive: (_) {},
            onTryAgain: () {},
            syncMenu: const DrivesSyncMenu(),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
        // The heading's tinted container: the outermost animated container
        // around the button.
        final heading = tester.getRect(find
            .ancestor(
              of: find.byKey(DrivesSyncMenu.moreKey),
              matching: find.byType(AnimatedContainer),
            )
            .last);
        final chevron = tester.getRect(find.byKey(DrivesSyncMenu.moreKey));

        expect(chevron.right, lessThanOrEqualTo(width),
            reason: 'the chevron is on screen, so the button fits the row');
        expect(
            chevron.right, moreOrLessEquals(heading.right - 16 - 1, epsilon: 1),
            reason: 'the button ends where the heading does, inside its '
                'padding, however much room the title leaves it');
        // On a wide screen there is room to spare, and a box that filled it
        // would be a slab across the heading; it stays the width of its
        // label. On a phone it is capped at half the row instead.
        expect(
          tester.getSize(find.byKey(DrivesSyncMenu.primaryKey)).width,
          width >= 1000 ? lessThan(320) : lessThanOrEqualTo(width / 2),
          reason: 'as wide as its label, never a slab across the heading',
        );
      });
    }

    testWidgets('fits a 320px phone at twice the text size', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      listed(walked: false);

      await tester.pumpWidget(host(drivesList: drivesList, textScale: 2));
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(DrivesSyncMenu.primaryKey)).height,
        tester.getSize(find.byKey(DrivesSyncMenu.moreKey)).height,
        reason: 'the halves stay one control as the text grows',
      );
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

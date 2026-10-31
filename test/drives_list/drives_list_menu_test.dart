import 'dart:async';

import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/drives_list/domain/drive_list_item.dart';
import 'package:ardrive/drives_list/presentation/drive_actions_menu.dart';
import 'package:ardrive/drives_list/presentation/drive_list_row.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';

/// The per-drive menu, where the drives are listed.
///
/// Two things it has to get right that nothing else checks: an action that
/// does not apply is absent rather than drawn and inert, and the menu does not
/// cost a phone any row height - the rows are the page, and a menu that pushed
/// each of them 16px taller would be the most expensive thing on it.
void main() {
  late MockSyncBloc syncCubit;
  late MockProfileCubit profileCubit;
  late StreamController<SyncState> syncStates;

  setUpAll(() {
    registerFallbackValue(SyncTrigger.background);
  });

  setUp(() {
    syncCubit = MockSyncBloc();
    profileCubit = MockProfileCubit();
    when(() => profileCubit.state)
        .thenReturn(ProfileLoggedIn(user: getTestUser(), useTurbo: false));
    syncStates = StreamController<SyncState>.broadcast();

    whenListen(syncCubit, syncStates.stream, initialState: SyncIdle());
    when(() => syncCubit.syncProgress).thenReturn(SyncProgress.initial());
    when(() => syncCubit.startSyncForDrive(
          driveId: any(named: 'driveId'),
          deepSync: any(named: 'deepSync'),
          trigger: any(named: 'trigger'),
        )).thenAnswer((_) async => true);
  });

  tearDown(() async {
    await syncStates.close();
  });

  Drive drive({
    String id = 'drive-a',
    String name = 'Photos',
    bool isHidden = false,
  }) =>
      Drive(
        id: id,
        rootFolderId: '$id-root',
        ownerAddress: 'owner',
        name: name,
        privacy: 'public',
        isHidden: isHidden,
        dateCreated: DateTime(2026, 3, 4),
        lastUpdated: DateTime(2026, 3, 4),
      );

  DriveListItem item() => DriveListItem(
        id: 'drive-a',
        name: 'Photos',
        isPrivate: false,
        isSharedWithMe: false,
        isHidden: false,
        dateCreated: DateTime(2026, 3, 4),
        hasBeenWalked: false,
        fileCount: null,
        totalSize: null,
        lastSyncedAt: null,
        isSyncing: false,
        lastSyncFailed: false,
      );

  Widget host(Widget child, {double textScale = 1}) => ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
          // ArDriveDropdown puts its items in a portal; without one the menu
          // renders but can never open, and every assertion below about what
          // it offers would pass by finding nothing.
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: Portal(
                child: Scaffold(
                  body: MultiBlocProvider(
                    providers: [
                      BlocProvider<SyncCubit>.value(value: syncCubit),
                      // Detach is for a drive you don't own, when signed in,
                      // as Your drives always is.
                      BlocProvider<ProfileCubit>.value(value: profileCubit),
                    ],
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> openMenu(
    WidgetTester tester, {
    required bool isOwner,
    bool isHidden = false,
    bool isSyncing = false,
    Size size = const Size(1200, 900),
  }) async {
    if (isSyncing) {
      when(() => syncCubit.state).thenReturn(SyncInProgress());
    }

    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      host(
        Align(
          alignment: Alignment.topLeft,
          child: DriveActionsMenu(
            isSynced: true,
            drive: drive(isHidden: isHidden),
            isOwner: isOwner,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(DriveActionsMenu));
    await tester.pumpAndSettle();
  }

  // #30: More info on a drive not synced here went to its "not synced" card,
  // and the request lingered to open the panel by itself later.
  group('More info', () {
    Future<void> openWith(
      WidgetTester tester, {
      required bool isSynced,
      void Function(String id)? onShowDetails,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(host(Align(
        alignment: Alignment.topLeft,
        child: DriveActionsMenu(
          isSynced: isSynced,
          drive: drive(),
          isOwner: true,
          onShowDetails: onShowDetails,
        ),
      )));
      await tester.tap(find.byType(DriveActionsMenu));
      await tester.pumpAndSettle();
    }

    testWidgets('on desktop opens the page\'s own details, synced or not',
        (tester) async {
      final shown = <String>[];
      await openWith(tester, isSynced: false, onShowDetails: shown.add);

      await tester.tap(find.text('More info'));
      await tester.pumpAndSettle();

      expect(shown, ['drive-a']);
    });

    testWidgets('on a phone is left out for a drive not synced here',
        (tester) async {
      await openWith(tester, isSynced: false);

      expect(find.text('More info'), findsNothing);
    });

    testWidgets('on a phone is offered for a synced drive', (tester) async {
      await openWith(tester, isSynced: true);

      expect(find.text('More info'), findsOneWidget);
    });
  });

  group('the sync it offers, while a sync runs', () {
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

    testWidgets('is live when nothing is running', (tester) async {
      await openMenu(tester, isOwner: true);

      expect(itemNamed(tester, 'Sync this drive').isDisabled, isFalse);
      expect(entryNamed(tester, 'Sync this drive').onClick, isNotNull);
    });

    testWidgets('says it is unavailable rather than doing nothing',
        (tester) async {
      // `SyncCubit.startSyncForDrive` refuses outright while a sync runs - one
      // at a time, no queue. An item that looks normal, closes the menu and
      // drops the request is a lie, and `isDisabled` is what draws it as
      // unavailable: ArDriveDropdownItemTile picks its colours off the flag
      // alone, so a null callback on its own leaves it looking live.
      await openMenu(tester, isOwner: true, isSyncing: true);

      expect(itemNamed(tester, 'Sync this drive').isDisabled, isTrue);
      expect(entryNamed(tester, 'Sync this drive').onClick, isNull);
    });

    testWidgets(
        'is unavailable while the drive list refreshes, as the page\'s '
        'Sync is', (tester) async {
      // A refresh of the drive list is not a sync, but the page's own Sync is
      // unavailable during it, and the page gives one answer.
      when(() => syncCubit.state).thenReturn(SyncLoadingDrives());
      await openMenu(tester, isOwner: true);

      expect(itemNamed(tester, 'Sync this drive').isDisabled, isTrue);
      expect(entryNamed(tester, 'Sync this drive').onClick, isNull);
    });

    testWidgets('and the other actions are untouched', (tester) async {
      // A running sync has nothing to do with renaming or sharing a drive.
      await openMenu(tester, isOwner: true, isSyncing: true);

      expect(itemNamed(tester, 'Rename drive').isDisabled, isFalse);
      expect(itemNamed(tester, 'Share drive').isDisabled, isFalse);
      expect(entryNamed(tester, 'Share drive').onClick, isNotNull);
    });
  });

  /// The menu button's target is centred in the row's end gutter, a few
  /// pixels from the screen's edge. On a phone the menu keeps the 16 px gutter
  /// rather than lining up with the target.
  group('where the menu opens', () {
    Future<Rect> menuAt(WidgetTester tester, Size size) async {
      // Starts from nothing, so a menu left open by an earlier call is gone.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      // The view as well as the surface: the menu reads the screen's width
      // from MediaQuery, which follows the view.
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        host(
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: DriveActionsMenu(
                isSynced: true,
                drive: drive(),
                isOwner: true,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(DriveActionsMenu));
      await tester.pumpAndSettle();

      return tester.getRect(
        find.widgetWithText(ArDriveDropdownItemTile, 'Share drive'),
      );
    }

    testWidgets('keeps the 16 px gutter on a phone, not the button\'s edge',
        (tester) async {
      // The button's target ends 4 px from the edge here, as it does in a
      // row's gutter. The menu card's own inset is the same on both screens,
      // so the difference between them is the pull towards the gutter.
      final wide = await menuAt(tester, const Size(1200, 900));
      final phone = await menuAt(tester, const Size(390, 844));

      final wideGap = (1200 - 4) - wide.right;
      final phoneGap = (390 - 4) - phone.right;
      expect(phoneGap - wideGap, 16 - 4);
    });
  });

  group('what the menu offers', () {
    testWidgets('a drive you own: sync, rename, share, hide - and no detach',
        (tester) async {
      await openMenu(tester, isOwner: true);

      expect(find.text('Sync this drive'), findsOneWidget);
      expect(find.text('Rename drive'), findsOneWidget);
      expect(find.text('Share drive'), findsOneWidget);
      expect(find.text('Hide'), findsOneWidget);
      expect(find.text('Unhide'), findsNothing);
      // There is nothing to detach from: it is your drive.
      expect(find.text('Detach drive'), findsNothing);
    });

    testWidgets('a drive shared with you: detach, and nothing owners-only',
        (tester) async {
      await openMenu(tester, isOwner: false);

      expect(find.text('Sync this drive'), findsOneWidget);
      expect(find.text('Share drive'), findsOneWidget);
      expect(find.text('Detach drive'), findsOneWidget);
      // Renaming and hiding are the owner's, and an item that cannot work is
      // worse than one that is not there.
      expect(find.text('Rename drive'), findsNothing);
      expect(find.text('Hide'), findsNothing);
      expect(find.text('Unhide'), findsNothing);
    });

    testWidgets('a hidden drive is offered the other half of the pair',
        (tester) async {
      await openMenu(tester, isOwner: true, isHidden: true);

      expect(find.text('Unhide'), findsOneWidget);
      expect(find.text('Hide'), findsNothing);
    });
  });

  // The menu is ArDriveDropdown. Its items were not buttons, so with the
  // browser's accessibility tree on the web gave them no role and no name.
  group('with a screen reader', () {
    void expectButtons(
      WidgetTester tester,
      List<String> names, {
      Set<String> disabled = const {},
    }) {
      for (final name in names) {
        final item = find.bySemanticsLabel(name);
        expect(item, findsOneWidget, reason: name);
        expect(
          tester.getSemantics(item),
          containsSemantics(
            label: name,
            isButton: true,
            hasEnabledState: true,
            isEnabled: !disabled.contains(name),
            hasTapAction: true,
          ),
          reason: name,
        );
      }
    }

    testWidgets('hears every item of a drive you own, each a button',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await openMenu(tester, isOwner: true);

      expectButtons(tester, [
        'Sync this drive',
        'Rename drive',
        'More info',
        'Share drive',
        'Create snapshot',
        'Export contents',
        'Download',
        'Hide',
      ]);

      semantics.dispose();
    });

    testWidgets('and of a drive shared with you', (tester) async {
      final semantics = tester.ensureSemantics();
      await openMenu(tester, isOwner: false);

      expectButtons(tester, [
        'Sync this drive',
        'More info',
        'Share drive',
        'Export contents',
        'Download',
        'Detach drive',
      ]);

      semantics.dispose();
    });

    testWidgets('hears that the sync is unavailable while one runs',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await openMenu(tester, isOwner: true, isSyncing: true);

      expectButtons(
        tester,
        ['Sync this drive', 'Rename drive'],
        disabled: {'Sync this drive'},
      );

      semantics.dispose();
    });
  });

  group('reaching it', () {
    testWidgets('the tap target is big enough for a finger', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        host(
          Align(
            alignment: Alignment.topLeft,
            child:
                DriveActionsMenu(isSynced: true, drive: drive(), isOwner: true),
          ),
        ),
      );

      final target = tester.getSize(find.byType(DriveActionsMenu));

      expect(target.width, greaterThanOrEqualTo(48));
      expect(target.height, greaterThanOrEqualTo(48));
    });

    /// The tooltip and the button's own label both reached the screen reader,
    /// which read it as "Show menu Show menu".
    testWidgets('a screen reader hears its name once', (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        host(
          Align(
            alignment: Alignment.topLeft,
            child:
                DriveActionsMenu(isSynced: true, drive: drive(), isOwner: true),
          ),
        ),
      );

      final menu = find.bySemanticsLabel('Show menu');
      expect(menu, findsOneWidget);
      final node = tester.getSemantics(menu);
      expect(
        node,
        containsSemantics(
          label: 'Show menu',
          isButton: true,
          hasTapAction: true,
        ),
      );
      // The web engine reads a node's label and its tooltip out together, so
      // the tooltip's copy of the name is what made it "Show menu Show menu".
      expect(node.getSemanticsData().tooltip, isEmpty);

      semantics.dispose();
    });

    testWidgets('and costs a phone no row height at all', (tester) async {
      // 320px is the stacked card, which is what a phone draws. The row's
      // height there is set by its own content; a menu that set it instead
      // would have made every row on the page taller.
      await tester.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        host(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              child: DriveListRow(
                drive: item(),
                showsColumns: false,
                onOpen: () {},
                menu: DriveActionsMenu(
                    isSynced: true, drive: drive(), isOwner: true),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(DriveActionsMenu), findsOneWidget,
          reason: 'no menu in the row means the comparison below is vacuous');

      final row = tester.getSize(find.byType(DriveListRow)).height;

      // The row's content with its padding: what the row would measure if the
      // menu were not beside it. Compared against the row rather than against
      // a second render, because a second render is only equal for as long as
      // the content happens to be taller than whatever the menu asks for -
      // which the test font makes true at 320px whatever the menu does.
      final content = tester
          .getSize(
            find
                .descendant(
                  of: find.byType(InkWell),
                  matching: find.byType(Padding),
                )
                .first,
          )
          .height;

      expect(content, greaterThan(0));

      // The row is its content plus the hairline divider it draws under it,
      // and nothing else. Anything the menu added would show up here.
      expect(row, content + 1,
          reason: 'the menu set the row height instead of fitting inside it');
    });

    testWidgets('the header reserves the same gutter the rows do',
        (tester) async {
      // Otherwise every heading sits 56px left of the column beneath it.
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        host(
          SizedBox(
            width: 1000,
            child: Column(
              children: [
                const DriveListHeader(),
                DriveListRow(
                  drive: item(),
                  showsColumns: true,
                  onOpen: () {},
                  menu: DriveActionsMenu(
                      isSynced: true, drive: drive(), isOwner: true),
                ),
              ],
            ),
          ),
        ),
      );

      final heading = tester.getRect(find.text('Last synced'));
      final value = tester.getRect(find.text('Not synced on this device'));

      expect(value.left, closeTo(heading.left, 1),
          reason: 'the heading and the column under it are laid out in '
              'different widths');
    });
  });

  /// The button lives at the trailing edge of a row, and the menu is wider
  /// than the room to its left on a phone. `ArDriveDropdown` was discarding
  /// the anchor whenever `calculateVerticalAlignment` was also supplied - so
  /// this menu, which supplies both, was re-anchored to its button's
  /// bottom-*left* with no shifting, and opened 51px off the screen with every
  /// item's leading icon outside the viewport.
  group('the menu opens inside the screen it is on', () {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('320px at ${scale}x, anchored at the trailing edge',
          (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          host(
            Align(
              alignment: Alignment.topRight,
              child: DriveActionsMenu(
                  isSynced: true, drive: drive(), isOwner: true),
            ),
            textScale: scale,
          ),
        );

        await tester.tap(find.byType(DriveActionsMenu));
        await tester.pumpAndSettle();

        final tiles = find.byType(ArDriveDropdownItemTile);
        expect(tiles, findsWidgets);

        for (var i = 0; i < tiles.evaluate().length; i++) {
          final left = tester.getTopLeft(tiles.at(i)).dx;
          expect(
            left,
            greaterThanOrEqualTo(0),
            reason: 'menu item $i starts ${-left}px off the left edge',
          );
        }
      });
    }
  });
}

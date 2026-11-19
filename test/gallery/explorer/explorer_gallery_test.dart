import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/entities/file_entity.dart' show Variant;
import 'package:ardrive/gallery/explorer/explorer_gallery.dart';
import 'package:ardrive/gallery/image_loader/gallery_image_loader.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart'
    show DriveExplorerItemTileTrailing;
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/pages/drive_detail/models/drive_table_columns.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../../test_utils/utils.dart';
import 'gallery_test_items.dart';

class _MockSyncCubit extends MockCubit<SyncState> implements SyncCubit {}

class _MockGlobalHideBloc extends MockBloc<GlobalHideEvent, GlobalHideState>
    implements GlobalHideBloc {}

/// Answers every fetch with a pixel, and keeps the log of what was asked.
class _FakeFetcher implements GalleryImageFetcher {
  final fetched = <String>[];

  @override
  Future<Uint8List> fetch(
    GalleryFetchTarget target, {
    required Future<void> cancelWhen,
  }) async {
    fetched.add(target.variant.txId);
    return Uint8List.fromList(const [0]);
  }
}

void main() {
  late MockProfileCubit profileCubit;
  late MockDriveDetailCubit detailCubit;
  late _MockSyncCubit syncCubit;
  late MockArDriveAuth auth;
  late _MockGlobalHideBloc hideBloc;
  late _FakeFetcher fetcher;
  late GalleryImageLoader loader;

  final drive = Drive(
    id: 'drive',
    rootFolderId: 'root',
    name: 'Photos',
    ownerAddress: getTestUser().walletAddress,
    dateCreated: DateTime(2026, 1, 1),
    lastUpdated: DateTime(2026, 1, 1),
    privacy: 'public',
    isHidden: false,
  );

  final oct = DateTime(2026, 10, 15);
  final sep = DateTime(2026, 9, 15);

  List<Variant> wide(String id) => [variant('thumb-$id', 800, 400)];

  setUpAll(() {
    registerFallbackValue(fileItem('fallback'));
    registerFallbackValue(<ArDriveDataTableItem>[]);
  });

  setUp(() {
    profileCubit = MockProfileCubit();
    detailCubit = MockDriveDetailCubit();
    syncCubit = _MockSyncCubit();
    auth = MockArDriveAuth();
    hideBloc = _MockGlobalHideBloc();
    fetcher = _FakeFetcher();
    loader = GalleryImageLoader(
      fetcher: fetcher,
      config: const GalleryLoaderConfig(idleDelay: Duration.zero),
    );
    whenListen(hideBloc, const Stream<GlobalHideState>.empty(),
        initialState: const HiddingItems(userHasHiddenDrive: false));
    when(() => auth.currentUser).thenReturn(getTestUser());
    whenListen(profileCubit, const Stream<ProfileState>.empty(),
        initialState: ProfileLoggedIn(user: getTestUser(), useTurbo: false));
    whenListen(syncCubit, const Stream<SyncState>.empty(),
        initialState: SyncIdle());
    when(() => detailCubit.selectedItems).thenReturn(const []);
    when(() => detailCubit.selectedItem).thenReturn(null);
    when(() => detailCubit.selectDataItem(any(),
            openDetails: any(named: 'openDetails'),
            openSelectedPage: any(named: 'openSelectedPage')))
        .thenAnswer((_) async {});
    when(() => detailCubit.openDataItem(any())).thenAnswer((_) async {});
    when(() => detailCubit.selectItems(any())).thenAnswer((_) async {});
  });

  tearDown(() => loader.dispose());

  /// The gallery in the explorer's providers, as a widget the test can
  /// rebuild with new props.
  Widget app(
    List<ArDriveDataTableItem> items, {
    ArDriveDataTableItem? selected,
    List<ArDriveDataTableItem> multi = const [],
    bool dark = false,
    bool lock = false,
    int? sortColumn,
    TableSort? sortOrder,
  }) =>
      ArDriveTheme(
        themeData: dark
            ? ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode())
            : lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
          home: Provider<ArDriveAuth>.value(
            value: auth,
            child: RepositoryProvider<GalleryImageLoader>.value(
              value: loader,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<ProfileCubit>.value(value: profileCubit),
                  BlocProvider<DriveDetailCubit>.value(value: detailCubit),
                  BlocProvider<SyncCubit>.value(value: syncCubit),
                  BlocProvider<GlobalHideBloc>.value(value: hideBloc),
                ],
                child: Portal(
                  child: Scaffold(
                    body: ExplorerGallery(
                      items: items,
                      drive: drive,
                      folderId: 'root',
                      selectedItem: selected,
                      multiSelected: multi,
                      sortColumn: sortColumn,
                      sortOrder: sortOrder,
                      lockMultiSelect: lock,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> pump(
    WidgetTester tester,
    Widget widget, {
    Size size = const Size(1000, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(widget);
    await tester.pump();
    await tester.pump();
  }

  Finder tileOf(String name) =>
      find.byWidgetPredicate((w) => w is ArDriveGalleryTile && w.name == name,
          description: 'tile $name');

  Future<void> mouseTap(WidgetTester tester, Finder tile,
      {int buttons = kPrimaryButton}) async {
    await tester.tap(tile, kind: PointerDeviceKind.mouse, buttons: buttons);
    await tester.pump();
  }

  final a =
      fileItem('a', name: 'Alfama.jpg', created: oct, variants: wide('a'));
  final b = fileItem('b', name: 'Pier.jpg', created: oct, variants: wide('b'));
  final c = fileItem('c', name: 'Dunes.jpg', created: oct, variants: wide('c'));
  final d = fileItem('d', name: 'Snow.jpg', created: sep, variants: wide('d'));
  final doc = fileItem('doc',
      name: 'Itinerary.pdf', contentType: 'application/pdf', created: sep);
  final trips = folderItem('trips', name: 'Trips');
  final all = <ArDriveDataTableItem>[a, b, c, d, doc, trips];

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('folders first, then months with their counts ($mode)',
        (tester) async {
      await pump(tester, app(all, dark: dark));

      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('September 2026'), findsOneWidget);
      expect(find.text('3 items'), findsOneWidget);
      expect(find.text('2 items'), findsOneWidget);

      // The folder is above the first month's header, which is above its
      // photos; the document is a quiet type tile.
      final folderY = tester.getTopLeft(tileOf('Trips')).dy;
      final headerY = tester.getTopLeft(find.text('October 2026')).dy;
      final photoY = tester.getTopLeft(tileOf('Alfama.jpg')).dy;
      expect(folderY, lessThan(headerY));
      expect(headerY, lessThan(photoY));
      expect(find.byKey(const ValueKey('gallery-folder-tile')), findsOneWidget);
      expect(find.byKey(const ValueKey('gallery-type-tile')), findsOneWidget);
    });
  }

  testWidgets('a photo is as wide as its thumbnail\'s shape says',
      (tester) async {
    await pump(tester, app([a]));
    final size = tester.getSize(tileOf('Alfama.jpg'));
    expect(size.width / size.height, closeTo(2, 0.02));
  });

  testWidgets('on a phone the rows are about 86 px', (tester) async {
    await pump(tester, app([a, b, c, d]), size: const Size(390, 800));
    // Rows fill the width, so a row is about, not exactly, the target.
    final height = tester.getSize(tileOf('Alfama.jpg')).height;
    expect(height, closeTo(galleryPhoneRowHeight, 15));
    expect(height, lessThan(galleryDesktopRowHeight));
  });

  group('the loader', () {
    testWidgets('fetches only what is on screen', (tester) async {
      final many = [
        for (var i = 0; i < 150; i++)
          fileItem('f$i', name: 'p$i.jpg', created: oct, variants: wide('f$i')),
      ];
      await pump(tester, app(many));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();

      expect(fetcher.fetched, isNotEmpty);
      expect(fetcher.fetched, contains('thumb-f0'));
      expect(fetcher.fetched, isNot(contains('thumb-f149')));

      // Everything asked for is on screen. The list builds a little past the
      // screen, and those tiles must wait until they are seen.
      final viewport = tester.view.physicalSize.height;
      for (final txId in fetcher.fetched) {
        final name = 'p${txId.substring('thumb-f'.length)}.jpg';
        final rect = tester.getRect(tileOf(name));
        expect(rect.top, lessThan(viewport), reason: '$name was fetched');
        expect(rect.bottom, greaterThan(0), reason: '$name was fetched');
      }
      // And the built-but-below-the-fold ones really exist: the list builds
      // a little past the screen, which finders count as offstage.
      Finder anyTile(String name) => find.byWidgetPredicate(
          (w) => w is ArDriveGalleryTile && w.name == name,
          skipOffstage: false);
      final below = [
        for (var i = 0; i < 150; i++)
          if (anyTile('p$i.jpg').evaluate().isNotEmpty &&
              tester.getRect(anyTile('p$i.jpg')).top >= viewport)
            i,
      ];
      expect(below, isNotEmpty);
      for (final i in below) {
        expect(fetcher.fetched, isNot(contains('thumb-f$i')));
      }
    });
  });

  group('the row model', () {
    testWidgets('a click selects and does not open', (tester) async {
      await pump(tester, app(all));
      await mouseTap(tester, tileOf('Pier.jpg'));
      await tester.pump(const Duration(seconds: 1));

      verify(() => detailCubit.selectDataItem(b, openDetails: false)).called(1);
      verifyNever(() => detailCubit.openDataItem(any()));
    });

    testWidgets('a double-click opens', (tester) async {
      await pump(tester, app(all));
      await mouseTap(tester, tileOf('Pier.jpg'));
      await mouseTap(tester, tileOf('Pier.jpg'));
      await tester.pump(const Duration(seconds: 1));

      verify(() => detailCubit.openDataItem(b)).called(1);
    });

    testWidgets('a touch tap opens, as it does in the list', (tester) async {
      await pump(tester, app(all));
      await tester.tap(tileOf('Pier.jpg')); // touch by default
      await tester.pump(const Duration(seconds: 1));

      verify(() => detailCubit.openDataItem(b)).called(1);
      verifyNever(() => detailCubit.selectDataItem(any(),
          openDetails: any(named: 'openDetails')));
    });

    testWidgets('Enter opens the tile with focus', (tester) async {
      await pump(tester, app(all));
      await mouseTap(tester, tileOf('Pier.jpg'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      verify(() => detailCubit.openDataItem(b)).called(1);
    });

    testWidgets('Shift selects the range from the last click', (tester) async {
      await pump(tester, app(all));
      await mouseTap(tester, tileOf('Alfama.jpg'));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await mouseTap(tester, tileOf('Dunes.jpg'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      final chosen = verify(() => detailCubit.selectItems(captureAny()))
          .captured
          .last as List<ArDriveDataTableItem>;
      expect(chosen.map((e) => e.id), ['a', 'b', 'c']);
    });

    testWidgets('Ctrl adds to the selection and takes from it', (tester) async {
      await pump(tester, app(all, selected: a));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await mouseTap(tester, tileOf('Dunes.jpg'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      var chosen = verify(() => detailCubit.selectItems(captureAny()))
          .captured
          .last as List<ArDriveDataTableItem>;
      expect(chosen.map((e) => e.id), ['a', 'c']);

      // Now two are chosen; Ctrl on one of them takes it out.
      clearInteractions(detailCubit);
      when(() => detailCubit.selectedItems).thenReturn([a, c]);
      await tester.pumpWidget(app(all, multi: [a, c]));
      // Past the double-click window, so this is a second click, not a
      // double-click.
      await tester.pump(const Duration(seconds: 1));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await mouseTap(tester, tileOf('Dunes.jpg'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      chosen = verify(() => detailCubit.selectItems(captureAny())).captured.last
          as List<ArDriveDataTableItem>;
      expect(chosen.map((e) => e.id), ['a']);
    });

    testWidgets('a plain click after a multi-selection ends it',
        (tester) async {
      await pump(tester, app(all, multi: [a, b]));
      await mouseTap(tester, tileOf('Dunes.jpg'));
      verify(() => detailCubit.selectItems(const [])).called(1);
      verify(() => detailCubit.selectDataItem(c, openDetails: false)).called(1);
    });

    testWidgets('Escape clears a multi-selection', (tester) async {
      await pump(tester, app(all, multi: [a, b]));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      verify(() => detailCubit.selectItems(const [])).called(1);
    });

    testWidgets('Escape with nothing chosen does nothing', (tester) async {
      await pump(tester, app(all));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      verifyNever(() => detailCubit.selectItems(any()));
    });

    testWidgets('a sync holding multi-select shut makes Shift a plain click',
        (tester) async {
      await pump(tester, app(all, lock: true));
      await mouseTap(tester, tileOf('Alfama.jpg'));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await mouseTap(tester, tileOf('Dunes.jpg'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      verifyNever(() => detailCubit.selectItems(any()));
      verify(() => detailCubit.selectDataItem(c, openDetails: false)).called(1);
    });

    testWidgets('selected tiles are marked, the selection is the multi one',
        (tester) async {
      await pump(tester, app(all, selected: d, multi: [a, b]));
      expect(find.byKey(const ValueKey('gallery-tile-selected')),
          findsNWidgets(2));
    });

    testWidgets('on a phone, a long press starts selecting and taps then add',
        (tester) async {
      await pump(tester, app(all), size: const Size(390, 800));
      await tester.longPress(tileOf('Pier.jpg'));
      final chosen = verify(() => detailCubit.selectItems(captureAny()))
          .captured
          .last as List<ArDriveDataTableItem>;
      expect(chosen.map((e) => e.id), ['b']);

      clearInteractions(detailCubit);
      when(() => detailCubit.selectedItems).thenReturn([b]);
      await tester.pumpWidget(app(all, multi: [b]));
      await tester.pump();
      await tester.tap(tileOf('Dunes.jpg'));
      await tester.pump(const Duration(seconds: 1));
      verifyNever(() => detailCubit.openDataItem(any()));
      final next = verify(() => detailCubit.selectItems(captureAny()))
          .captured
          .last as List<ArDriveDataTableItem>;
      expect(next.map((e) => e.id), ['b', 'c']);
    });
  });

  group('the menu', () {
    Future<List<String>> openedMenu(WidgetTester tester) async {
      await tester.pumpAndSettle();
      return tester
          .widgetList<ArDriveDropdownItemTile>(
              find.byType(ArDriveDropdownItemTile))
          .map((t) => t.name)
          .toList();
    }

    testWidgets('a right-click chooses the tile and opens the list row\'s menu',
        (tester) async {
      // The list's row menu for the same file.
      await pump(
        tester,
        ArDriveTheme(
          themeData: lightTheme(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MultiBlocProvider(
              providers: [
                BlocProvider<ProfileCubit>.value(value: profileCubit),
                BlocProvider<DriveDetailCubit>.value(value: detailCubit),
                BlocProvider<SyncCubit>.value(value: syncCubit),
                BlocProvider<GlobalHideBloc>.value(value: hideBloc),
              ],
              child: Portal(
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: DriveExplorerItemTileTrailing(item: b, drive: drive),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(ArDriveDropdown));
      final listMenu = await openedMenu(tester);
      expect(listMenu, isNotEmpty);

      await pump(tester, app(all));
      await mouseTap(tester, tileOf('Pier.jpg'),
          buttons: kSecondaryMouseButton);
      final galleryMenu = await openedMenu(tester);

      expect(galleryMenu, listMenu);
      // And the tile was chosen first, as a click does.
      verify(() => detailCubit.selectDataItem(b, openDetails: false)).called(1);
    });

    testWidgets('a folder\'s tile has the list\'s folder menu', (tester) async {
      await pump(tester, app(all));
      await mouseTap(tester, tileOf('Trips'), buttons: kSecondaryMouseButton);
      final menu = await openedMenu(tester);
      expect(menu, contains('Open'));
      expect(menu, isNot(contains('Preview')));
    });
  });

  group('the keyboard', () {
    String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

    testWidgets('arrows move between tiles, row-aware', (tester) async {
      await pump(tester, app([a, b, c, d, doc]), size: const Size(1000, 800));
      await mouseTap(tester, tileOf('Alfama.jpg'));
      expect(focused(), 'Alfama.jpg');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(focused(), 'Pier.jpg');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(focused(), 'Alfama.jpg');

      // Down goes to the row below, across the next month's header, and lands
      // on the tile nearest across: the first of September's.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump();
      expect(focused(), 'Snow.jpg');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.pump();
      expect(focused(), 'Alfama.jpg');
    });

    testWidgets('moving past the first and last tile stays put',
        (tester) async {
      await pump(tester, app([a, b]));
      await mouseTap(tester, tileOf('Alfama.jpg'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(focused(), 'Alfama.jpg');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(focused(), 'Pier.jpg');
    });
  });

  group('for a screen reader', () {
    testWidgets('a tile says its name and type, and whether it is chosen',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, app(all, selected: b));

      SemanticsNode node(String name) => tester.getSemantics(tileOf(name));

      expect(node('Pier.jpg').label, 'Pier.jpg, JPEG image');
      expect(node('Pier.jpg').hasFlag(SemanticsFlag.isSelected), isTrue);
      expect(node('Alfama.jpg').hasFlag(SemanticsFlag.isSelected), isFalse);
      expect(node('Trips').label, 'Trips, Folder');
      expect(node('Itinerary.pdf').label, 'Itinerary.pdf, PDF');
      expect(node('Pier.jpg').hasFlag(SemanticsFlag.isButton), isTrue);
      handle.dispose();
    });

    testWidgets('a month header is a header', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, app(all));
      final node = tester.getSemantics(find.text('October 2026'));
      expect(node.hasFlag(SemanticsFlag.isHeader), isTrue);
      handle.dispose();
    });
  });

  testWidgets('hidden items are not shown (the caller filters them)',
      (tester) async {
    // The list filters hidden rows before the table; the gallery is given the
    // same rows, so what it shows is what it is given.
    await pump(tester, app([a, b]));
    expect(tileOf('Alfama.jpg'), findsOneWidget);
    expect(tileOf('Dunes.jpg'), findsNothing);
  });

  testWidgets('the list\'s sort is the gallery\'s: Name, Alfama first',
      (tester) async {
    final z = fileItem('z', name: 'Zoo.jpg', created: oct, variants: wide('z'));
    final m = fileItem('m', name: 'Map.jpg', created: oct, variants: wide('m'));
    await pump(
      tester,
      app([z, m, a], sortColumn: ColumnIndexes.name, sortOrder: TableSort.asc),
    );
    // Name ascending, as the list's header would have it.
    final expected = sortExplorerRows(
        [z, m, a], ColumnIndexes.name, TableSort.asc,
        typeLabel: (i) => i.contentType).map((e) => e.name).toList();
    final onScreen = [z, m, a].map((e) => e.name).toList()
      ..sort((x, y) => tester
          .getTopLeft(tileOf(x))
          .dx
          .compareTo(tester.getTopLeft(tileOf(y)).dx));
    expect(onScreen, expected);
  });

  testWidgets('a details panel narrowing the gallery keeps desktop rows',
      (tester) async {
    final many = [
      for (var i = 0; i < 6; i++)
        fileItem('n$i', name: 'n$i.jpg', created: oct, variants: wide('n$i'))
    ];
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 600, child: app(many)),
    ));
    await tester.pump();
    await tester.pump();
    expect(tester.getSize(tileOf('n0.jpg')).height,
        greaterThan(galleryPhoneRowHeight * 1.5));
  });

  group('on a phone', () {
    testWidgets('folders, headers and tiles keep the 16 px side gutter',
        (tester) async {
      await pump(tester, app(all), size: const Size(390, 800));
      for (final name in ['Trips', 'Alfama.jpg', 'Pier.jpg']) {
        final rect = tester.getRect(tileOf(name));
        expect(rect.left, greaterThanOrEqualTo(16), reason: name);
        expect(rect.right, lessThanOrEqualTo(390 - 16), reason: name);
      }
      expect(
          tester
              .getTopLeft(
                  find.byKey(const ValueKey('gallery-month-select')).first)
              .dx,
          greaterThanOrEqualTo(16));
      // Rows fill the width between the gutters.
      final row = tester.getRect(tileOf('Alfama.jpg'));
      expect(row.left, 16);
    });
  });

  group('month select', () {
    Finder control() => find.byKey(const ValueKey('gallery-month-select'));

    List<String> lastChosen() =>
        (verify(() => detailCubit.selectItems(captureAny())).captured.last
                as List<ArDriveDataTableItem>)
            .map((e) => e.id)
            .toList();

    testWidgets('on a phone the control is always there, and selects the month',
        (tester) async {
      await pump(tester, app(all), size: const Size(390, 800));
      expect(control(), findsNWidgets(2));
      // October: a, b, c.
      await tester.tap(control().first);
      expect(lastChosen(), ['a', 'b', 'c']);
    });

    testWidgets('on a desktop it shows when the header is hovered',
        (tester) async {
      await pump(tester, app(all));
      expect(control(), findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('October 2026')));
      await tester.pump();
      expect(control(), findsOneWidget);
      await tester.tap(control());
      expect(lastChosen(), ['a', 'b', 'c']);
    });

    testWidgets('a month already chosen is taken out again', (tester) async {
      when(() => detailCubit.selectedItems).thenReturn([a, b, c, d]);
      await pump(tester, app(all, multi: [a, b, c, d]));
      // Shown without hover: something in it is chosen.
      expect(control(), findsNWidgets(2));
      await tester.tap(control().first);
      expect(lastChosen(), ['d']);
    });

    testWidgets('a sync holding multi-select shut leaves no control',
        (tester) async {
      await pump(tester, app(all, lock: true), size: const Size(390, 800));
      expect(control(), findsNothing);
      verifyNever(() => detailCubit.selectItems(any()));
    });

    testWidgets('a screen reader hears the control and whether it is on',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, app(all, multi: [a, b, c]),
          size: const Size(390, 800));
      final node = tester.getSemantics(control().first);
      expect(node.label, contains('Select October 2026'));
      expect(node.hasFlag(SemanticsFlag.isChecked), isTrue);
      handle.dispose();
    });
  });

  group('month headers align with the tiles', () {
    testWidgets('text starts at the tiles\' left edge, at rest and on hover',
        (tester) async {
      await pump(tester, app(all));
      double left(Finder f) => tester.getTopLeft(f).dx;
      final tiles = left(tileOf('Alfama.jpg'));
      expect(left(find.text('October 2026')), tiles);
      expect(left(tileOf('Trips')), tiles);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('October 2026')));
      await tester.pump();
      expect(
          find.byKey(const ValueKey('gallery-month-select')), findsOneWidget);
      expect(left(find.text('October 2026')), tiles);
      // The control sits after the count, not before the name.
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('gallery-month-select')))
            .dx,
        greaterThan(left(find.text('3 items'))),
      );
    });

    testWidgets('on a phone the same, inside the gutter', (tester) async {
      await pump(tester, app(all), size: const Size(390, 800));
      expect(tester.getTopLeft(find.text('October 2026')).dx, 16);
      expect(tester.getTopLeft(tileOf('Alfama.jpg')).dx, 16);
    });
  });

  group('quiet type tiles', () {
    for (final dark in [false, true]) {
      testWidgets(
          'portrait 3:4, a quiet fill and muted icon and name '
          '(${dark ? 'dark' : 'light'})', (tester) async {
        await pump(tester, app([doc], dark: dark));
        final size = tester.getSize(tileOf('Itinerary.pdf'));
        expect(size.width / size.height, closeTo(3 / 4, 0.02));

        final tokens = ArDriveTheme.of(tester.element(find.byType(Scaffold)))
            .themeData
            .colorTokens;
        final fill = tester.widget<ColoredBox>(
            find.byKey(const ValueKey('gallery-type-tile')));
        expect(fill.color, tokens.containerL1);
        // Closer to the page than a photo's skeleton (containerL2).
        expect(fill.color, isNot(tokens.containerL2));

        final tile = find.byKey(const ValueKey('gallery-type-tile'));
        final icon = tester.widget<Icon>(
            find.descendant(of: tile, matching: find.byType(Icon)));
        expect(icon.color, tokens.iconLow);
        final name = tester.widget<Text>(
            find.descendant(of: tile, matching: find.text('Itinerary.pdf')));
        expect(name.style!.color, tokens.textMid);
        expect(name.maxLines, 2);
      });
    }

    testWidgets('stay in date order among the photos', (tester) async {
      final newer = fileItem('n',
          name: 'Notes.md',
          contentType: 'text/markdown',
          created: DateTime(2026, 10, 20));
      await pump(
          tester,
          app([a, newer, b],
              sortColumn: ColumnIndexes.dateCreated, sortOrder: TableSort.asc));
      // Within October, in the list's date order: the notes sit between.
      Offset x(String n) => tester.getTopLeft(tileOf(n));
      final order = ['Alfama.jpg', 'Notes.md', 'Pier.jpg']..sort((p, q) {
          final dy = x(p).dy.compareTo(x(q).dy);
          return dy != 0 ? dy : x(p).dx.compareTo(x(q).dx);
        });
      final expected = sortExplorerRows(
          [a, newer, b], ColumnIndexes.dateCreated, TableSort.asc,
          typeLabel: (i) => i.contentType).map((e) => e.name).toList();
      expect(order, expected);
    });
  });
}

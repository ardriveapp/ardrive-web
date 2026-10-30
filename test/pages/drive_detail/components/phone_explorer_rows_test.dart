import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../test_utils/mocks.dart';

/// The explorer on a phone draws its rows as the desktop table does: flat.
///
/// Each file was a filled, rounded card 5 px from the next, so the list
/// looked highlighted throughout, unlike the desktop table beside it.
void main() {
  final drive = Drive(
    id: 'drive',
    rootFolderId: 'root',
    name: 'Drive',
    ownerAddress: 'owner',
    dateCreated: DateTime(2026, 1, 1),
    lastUpdated: DateTime(2026, 1, 1),
    privacy: 'public',
    isHidden: false,
  );

  FileDataTableItem file(String name) => FileDataTableItem(
        driveId: 'drive',
        lastUpdated: DateTime(2026, 1, 1),
        name: name,
        size: 10,
        dateCreated: DateTime(2026, 1, 1),
        contentType: 'text/markdown',
        index: 0,
        isOwner: true,
        fileId: 'file-$name',
        parentFolderId: 'root',
        dataTxId: 'tx-$name',
        lastModifiedDate: DateTime(2026, 1, 1),
        metadataTx: null,
        dataTx: null,
        pinnedDataOwnerAddress: null,
      );

  final folder = FolderDataTableItem(
    driveId: 'drive',
    folderId: 'folder-photos',
    name: 'photos',
    lastUpdated: DateTime(2026, 1, 1),
    dateCreated: DateTime(2026, 1, 1),
    contentType: 'folder',
    index: 0,
    isOwner: true,
  );
  final notes = file('notes.md');
  final readme = file('readme.md');
  final items = <ArDriveDataTableItem>[folder, notes, readme];

  late MockDriveDetailCubit cubit;

  setUpAll(() => registerFallbackValue(notes));

  setUp(() {
    cubit = MockDriveDetailCubit();
    when(() => cubit.selectedItem).thenReturn(null);
    when(() => cubit.openFolder(folderId: any(named: 'folderId')))
        .thenAnswer((_) async {});
    when(() => cubit.selectDataItem(any())).thenAnswer((_) async {});
  });

  final themes = {
    'light': lightTheme(),
    'dark': ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode()),
  };

  Future<void> pump(
    WidgetTester tester,
    ArDriveThemeData theme, {
    ArDriveDataTableItem? selected,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ArDriveTheme(
        themeData: theme,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: BlocProvider<DriveDetailCubit>.value(
            value: cubit,
            child: Scaffold(
              body: ArDriveItemList(
                items: items,
                drive: drive,
                selectedItem: selected,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder row(ArDriveDataTableItem item) => find.ancestor(
        of: find.text(item.name),
        matching: find.byType(ArDriveItemListTile),
      );

  /// The row's own fill: the outermost box it draws.
  Color fill(WidgetTester tester, ArDriveDataTableItem item) => tester
      .widget<ColoredBox>(
        find.descendant(of: row(item), matching: find.byType(ColoredBox)).first,
      )
      .color;

  for (final MapEntry(key: name, value: theme) in themes.entries) {
    group('at 390 px, $name', () {
      testWidgets('a row at rest has no fill and no card', (tester) async {
        await pump(tester, theme);

        for (final item in items) {
          expect(fill(tester, item), Colors.transparent, reason: item.name);
          // The icon keeps its own tile; the row is not drawn on a card.
          expect(
            find.ancestor(
              of: find.text(item.name),
              matching: find.byType(ArDriveCard),
            ),
            findsNothing,
            reason: '${item.name} is not on a rounded card',
          );
        }
      });

      testWidgets('rows meet with no gap, edge to edge, finger tall',
          (tester) async {
        await pump(tester, theme);

        for (var i = 0; i < items.length; i++) {
          final box = tester.getRect(row(items[i]));
          expect(box.left, 0, reason: items[i].name);
          expect(box.width, 390, reason: items[i].name);
          expect(box.height, greaterThanOrEqualTo(48), reason: items[i].name);
          if (i > 0) {
            expect(box.top, tester.getRect(row(items[i - 1])).bottom,
                reason: '${items[i].name} sits on the row above');
          }
        }
      });

      testWidgets("the selected row has the table's selected colour",
          (tester) async {
        await pump(tester, theme, selected: notes);

        expect(fill(tester, notes), theme.tableTheme.selectedItemColor);
        expect(fill(tester, readme), Colors.transparent);
        expect(fill(tester, folder), Colors.transparent);
      });

      testWidgets("a pressed row has the table's hover colour", (tester) async {
        await pump(tester, theme);

        final press = await tester.startGesture(tester.getCenter(
          find.text(readme.name),
        ));
        await tester.pumpAndSettle();

        final ink = Material.of(tester.element(find.text(readme.name)));
        expect(
          ink,
          paints..rect(color: theme.tableTheme.hoverItemColor),
        );
        await press.up();
        await tester.pumpAndSettle();
      });
    });
  }

  // A row's lines are one short line each at a small text size, and its
  // icons are what decide its height: today the 34 px menu button and the
  // padding make 50. That is an accident of the menu button, not a rule, so
  // the row holds the table's row height itself. Both are checked: the
  // height a reader gets, and that it comes from the row's own minimum
  // rather than from whatever its tallest child happens to be.
  testWidgets("a row of short lines is still the table's row height",
      (tester) async {
    await pump(tester, lightTheme(), textScale: 0.5);

    for (final item in items) {
      expect(tester.getSize(row(item)).height,
          greaterThanOrEqualTo(ArDriveDataTable.rowHeight),
          reason: item.name);

      final ownMinimum = tester
          .widgetList<Container>(
            find.descendant(of: row(item), matching: find.byType(Container)),
          )
          .where((box) =>
              box.constraints?.minHeight == ArDriveDataTable.rowHeight);
      expect(ownMinimum, hasLength(1),
          reason: '${item.name} holds the row height itself');
    }
  });

  testWidgets('a tap opens a folder and selects a file', (tester) async {
    await pump(tester, lightTheme());

    await tester.tap(find.text(folder.name));
    await tester.pumpAndSettle();
    verify(() => cubit.openFolder(folderId: folder.id)).called(1);

    await tester.tap(find.text(readme.name));
    await tester.pumpAndSettle();
    verify(() => cubit.selectDataItem(readme)).called(1);
  });

  testWidgets('each row keeps its menu', (tester) async {
    await pump(tester, lightTheme());

    for (final item in items) {
      expect(
        find.descendant(
          of: row(item),
          matching: find.byType(DriveExplorerItemTileTrailing),
        ),
        findsOneWidget,
        reason: item.name,
      );
    }
  });
}

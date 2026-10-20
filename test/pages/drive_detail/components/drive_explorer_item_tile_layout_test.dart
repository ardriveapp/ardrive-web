import 'dart:io';

import 'package:ardrive/components/pin_indicator.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// How a file name shares a row with the controls on its right.
///
/// The row used to reserve 100 px for them whatever the row held, so a name
/// beside only the menu button was cut off with a gap in front of it, and the
/// cut showed as a fade. Widths here are taken in the real font: in the test
/// font every glyph is a square em and a width means nothing.
void main() {
  const longName = 'a-rather-long-file-name-that-will-not-fit-in-the-row.md';

  setUpAll(() async {
    final bytes = await File(
      'packages/ardrive_ui/assets/fonts/Wavehaus-95SemiBold.otf',
    ).readAsBytes();

    final loader = FontLoader('packages/ardrive_ui/Wavehaus')
      ..addFont(
        Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
      );

    await loader.load();
  });

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

  FileDataTableItem file(String name, {String? pinnedBy}) => FileDataTableItem(
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
        dataTxId: 'tx',
        lastModifiedDate: DateTime(2026, 1, 1),
        metadataTx: null,
        dataTx: null,
        pinnedDataOwnerAddress: pinnedBy,
      );

  FolderDataTableItem folder(String name, {bool ghost = false}) =>
      FolderDataTableItem(
        driveId: 'drive',
        folderId: 'folder-$name',
        name: name,
        lastUpdated: DateTime(2026, 1, 1),
        dateCreated: DateTime(2026, 1, 1),
        contentType: 'folder',
        index: 0,
        isOwner: true,
        isGhostFolder: ghost,
      );

  /// The explorer's table in its Name-only state, [width] wide.
  Future<void> pump(
    WidgetTester tester,
    List<ArDriveDataTableItem> items, {
    double width = 450,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
          home: Scaffold(
            body: Builder(builder: (context) {
              final typography = ArDriveTypographyNew.of(context);
              final colorTokens =
                  ArDriveTheme.of(context).themeData.colorTokens;

              return ArDriveDataTable<ArDriveDataTableItem>(
                columns: [
                  TableColumn('Name', 9, index: 0, canHide: false),
                  TableColumn('Size', 3, index: 1, isVisible: false),
                  TableColumn('Updated', 3, index: 2, isVisible: false),
                  TableColumn('Created', 3, index: 3, isVisible: false),
                  TableColumn('License', 2, index: 4, isVisible: false),
                ],
                rows: items,
                rowsPerPageText: 'Rows per page',
                buildRow: (item) => DriveExplorerItemTile(
                  name: item.name,
                  size: '10 B',
                  lastUpdated: item.lastUpdated,
                  dateCreated: item.dateCreated,
                  license: '',
                  onPressed: () {},
                  isHidden: false,
                  typography: typography,
                  dataTableItem: item,
                  colorTokens: colorTokens,
                ),
                leading: (_) => const SizedBox(width: 40, height: 40),
                trailingWidth: DriveExplorerItemTileTrailing.widthFor,
                trailing: (item) => DriveExplorerItemTileTrailing(
                  drive: drive,
                  item: item,
                ),
                onChangeMultiSelecting: (_) {},
                sortRows: (list, column, order) => list,
              );
            }),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder name(String text) => find.text(text);

  double gapBeforeMenu(WidgetTester tester, String text) {
    final nameRight = tester.getRect(name(text)).right;
    final menuLeft = tester.getRect(find.byType(HoverWidget).first).left;
    return menuLeft - nameRight;
  }

  testWidgets('a name that does not fit ends with an ellipsis', (tester) async {
    await pump(tester, [file(longName)]);

    final text = tester.widget<Text>(name(longName));
    expect(text.overflow, TextOverflow.ellipsis);

    final paragraph = tester.renderObject<RenderParagraph>(name(longName));
    expect(paragraph.didExceedMaxLines, isTrue);
  });

  testWidgets('hovering a name shows the full name', (tester) async {
    await pump(tester, [file(longName)]);

    final tooltip = find.ancestor(
      of: name(longName),
      matching: find.byWidgetPredicate(
        (w) => w is ArDriveTooltip && w.message == longName,
      ),
    );
    expect(tooltip, findsOneWidget);
  });

  testWidgets('beside only the menu button, a name is not cut short of it',
      (tester) async {
    await pump(tester, [file(longName)]);

    expect(gapBeforeMenu(tester, longName), lessThanOrEqualTo(40));
  });

  testWidgets('a name that fits is shown in full', (tester) async {
    await pump(tester, [file('notes.md')]);

    final paragraph = tester.renderObject<RenderParagraph>(name('notes.md'));
    expect(paragraph.didExceedMaxLines, isFalse);
  });

  testWidgets(
      'a Fix button and a pin indicator fit without covering the name'
      ' or the menu', (tester) async {
    await pump(tester, [
      folder('a-ghost-folder-with-a-fairly-long-name-to-repair', ghost: true),
      file(longName, pinnedBy: 'someone'),
    ]);

    expect(tester.takeException(), isNull);

    final fixRect = tester.getRect(find.text('Fix'));
    final ghostName = name('a-ghost-folder-with-a-fairly-long-name-to-repair');
    expect(tester.getRect(ghostName).right, lessThanOrEqualTo(fixRect.left));

    final menus = find.byType(HoverWidget);
    expect(fixRect.right, lessThanOrEqualTo(tester.getRect(menus.at(0)).left));

    final pin = tester.getRect(find.byType(PinIndicator));
    expect(tester.getRect(name(longName)).right, lessThanOrEqualTo(pin.left));
    expect(pin.right, lessThanOrEqualTo(tester.getRect(menus.at(1)).left));
  });

  group('the trailing controls fit the width reserved for them', () {
    /// The trailing controls alone, in [locale], with room to spare, so what
    /// is measured is what they ask for and not what a slot gave them.
    Future<double> usedWidth(
      WidgetTester tester,
      ArDriveDataTableItem item,
      Locale locale,
    ) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ArDriveApp(
          builder: (context) => MaterialApp(
            locale: locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  child: DriveExplorerItemTileTrailing(
                    drive: drive,
                    item: item,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final menu = tester.getRect(find.byType(HoverWidget));
      final leftmost = item is FolderDataTableItem
          ? tester.getRect(find.byType(ArDriveButton)).left
          : item is FileDataTableItem && item.pinnedDataOwnerAddress != null
              ? tester.getRect(find.byType(PinIndicator)).left
              : menu.left;

      return menu.right - leftmost;
    }

    const locales = AppLocalizations.supportedLocales;

    testWidgets('an owner\'s ghost folder, in every language', (tester) async {
      final slot = DriveExplorerItemTileTrailing.widthFor(
        folder('ghost', ghost: true),
      );

      final tooWide = <String>[];

      for (final locale in locales) {
        final used = await usedWidth(
          tester,
          folder('ghost', ghost: true),
          locale,
        );
        // ignore: avoid_print
        print('ghost $locale: $used of $slot');
        if (used > slot) tooWide.add('$locale: $used');
      }

      expect(tooWide, isEmpty, reason: 'wider than the $slot reserved');
    });

    testWidgets('a pinned file and a plain row', (tester) async {
      final pinned = file('pinned', pinnedBy: 'someone');
      final plain = file('plain');

      final pinnedUsed = await usedWidth(tester, pinned, const Locale('en'));
      final plainUsed = await usedWidth(tester, plain, const Locale('en'));
      // ignore: avoid_print
      print(
          'pinned $pinnedUsed of ${DriveExplorerItemTileTrailing.widthFor(pinned)}, '
          'plain $plainUsed of ${DriveExplorerItemTileTrailing.widthFor(plain)}');

      expect(
        pinnedUsed,
        lessThanOrEqualTo(DriveExplorerItemTileTrailing.widthFor(pinned)),
      );
      expect(
        plainUsed,
        lessThanOrEqualTo(DriveExplorerItemTileTrailing.widthFor(plain)),
      );
    });

    testWidgets('a ghost folder the reader does not own has no Fix button',
        (tester) async {
      final foreign = FolderDataTableItem(
        driveId: 'drive',
        folderId: 'folder-foreign',
        name: 'foreign',
        lastUpdated: DateTime(2026, 1, 1),
        dateCreated: DateTime(2026, 1, 1),
        contentType: 'folder',
        index: 0,
        isOwner: false,
        isGhostFolder: true,
      );

      expect(
        DriveExplorerItemTileTrailing.widthFor(foreign),
        DriveExplorerItemTileTrailing.widthFor(file('plain')),
      );
    });
  });
}

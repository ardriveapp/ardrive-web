import 'package:ardrive/drives_list/domain/drive_list_item.dart';
import 'package:ardrive/drives_list/presentation/drive_actions_menu.dart';
import 'package:ardrive/drives_list/presentation/drive_list_row.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:flutter_test/flutter_test.dart';

/// The per-drive menu, where the drives are listed.
///
/// Two things it has to get right that nothing else checks: an action that
/// does not apply is absent rather than drawn and inert, and the menu does not
/// cost a phone any row height - the rows are the page, and a menu that pushed
/// each of them 16px taller would be the most expensive thing on it.
void main() {
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
        dateCreated: DateTime(2026, 3, 4),
        hasBeenWalked: false,
        itemCount: null,
        totalSize: null,
        lastSyncedAt: null,
        isSyncing: false,
      );

  Widget host(Widget child) => ArDriveTheme(
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
          home: Portal(child: Scaffold(body: child)),
        ),
      );

  Future<void> openMenu(
    WidgetTester tester, {
    required bool isOwner,
    bool isHidden = false,
    Size size = const Size(1200, 900),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      host(
        Align(
          alignment: Alignment.topLeft,
          child: DriveActionsMenu(
            drive: drive(isHidden: isHidden),
            isOwner: isOwner,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(DriveActionsMenu));
    await tester.pumpAndSettle();
  }

  group('what the menu offers', () {
    testWidgets('a drive you own: sync, rename, share, hide - and no detach',
        (tester) async {
      await openMenu(tester, isOwner: true);

      expect(find.text('Sync This Drive'), findsOneWidget);
      expect(find.text('Rename Drive'), findsOneWidget);
      expect(find.text('Share Drive'), findsOneWidget);
      expect(find.text('Hide'), findsOneWidget);
      expect(find.text('Unhide'), findsNothing);
      // There is nothing to detach from: it is your drive.
      expect(find.text('Detach Drive'), findsNothing);
    });

    testWidgets('a drive shared with you: detach, and nothing owners-only',
        (tester) async {
      await openMenu(tester, isOwner: false);

      expect(find.text('Sync This Drive'), findsOneWidget);
      expect(find.text('Share Drive'), findsOneWidget);
      expect(find.text('Detach Drive'), findsOneWidget);
      // Renaming and hiding are the owner's, and an item that cannot work is
      // worse than one that is not there.
      expect(find.text('Rename Drive'), findsNothing);
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

  group('reaching it', () {
    testWidgets('the tap target is big enough for a finger', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        host(
          Align(
            alignment: Alignment.topLeft,
            child: DriveActionsMenu(drive: drive(), isOwner: true),
          ),
        ),
      );

      final target = tester.getSize(find.byType(DriveActionsMenu));

      expect(target.width, greaterThanOrEqualTo(48));
      expect(target.height, greaterThanOrEqualTo(48));
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
                onTap: () {},
                menu: DriveActionsMenu(drive: drive(), isOwner: true),
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
                  onTap: () {},
                  menu: DriveActionsMenu(drive: drive(), isOwner: true),
                ),
              ],
            ),
          ),
        ),
      );

      final heading = tester.getRect(find.text('Last synced'));
      final value = tester.getRect(find.text('Never synced'));

      expect(value.left, closeTo(heading.left, 1),
          reason: 'the heading and the column under it are laid out in '
              'different widths');
    });
  });
}

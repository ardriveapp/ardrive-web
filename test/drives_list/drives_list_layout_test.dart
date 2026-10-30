import 'package:ardrive/components/list_page/list_page_layout.dart';
import 'package:ardrive/components/list_page/list_table.dart';
import 'package:ardrive/drives_list/domain/drive_list_item.dart';
import 'package:ardrive/drives_list/domain/drive_scope.dart';
import 'package:ardrive/drives_list/presentation/drive_scope_rail.dart';
import 'package:ardrive/drives_list/presentation/drives_list_cubit.dart';
import 'package:ardrive/drives_list/presentation/drives_list_page.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The drives page's layout follows the design system: a title row named for
/// the scope in every state, with the page's sync control at its end, so the
/// page never moves when the list arrives; empty scopes drawn as the system's
/// empty state; one primary per view.
void main() {
  const syncKey = Key('sync-control');

  DriveListItem drive(String id) => DriveListItem(
        id: id,
        name: id,
        isPrivate: false,
        isSharedWithMe: false,
        isHidden: false,
        dateCreated: DateTime(2024, 3, 4),
        hasBeenWalked: true,
        fileCount: 2,
        totalSize: 100,
        lastSyncedAt: DateTime.now(),
        isSyncing: false,
        lastSyncFailed: false,
      );

  Future<void> pumpBody(
    WidgetTester tester,
    DrivesListState state, {
    DriveScope scope = DriveScope.all,
    double width = 1200,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 900));
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
          home: Scaffold(
            body: DrivesListBody(
              state: state,
              scope: scope,
              onOpenDrive: (_) {},
              onTryAgain: () {},
              syncMenu: const SizedBox(key: syncKey, width: 120, height: 40),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('the title row', () {
    final states = <String, DrivesListState>{
      'loading': const DrivesListLoading(),
      'could not be read': DrivesListUnavailable(),
      'an empty scope':
          const DrivesListLoaded(drives: [], scope: DriveScope.private),
      'the list': DrivesListLoaded(drives: [drive('a')]),
    };

    for (final entry in states.entries) {
      testWidgets('is there with the sync control: ${entry.key}',
          (tester) async {
        await pumpBody(tester, entry.value);

        expect(find.byType(ListPageTitleRow), findsOneWidget);
        expect(find.byKey(syncKey), findsOneWidget);
      });
    }

    testWidgets('sits at the same place while loading as over the list',
        (tester) async {
      await pumpBody(tester, const DrivesListLoading());
      final loading = tester.getRect(find.byType(ListPageTitleRow));
      final loadingSync = tester.getRect(find.byKey(syncKey));

      await pumpBody(tester, DrivesListLoaded(drives: [drive('a')]));

      expect(tester.getRect(find.byType(ListPageTitleRow)), loading);
      expect(tester.getRect(find.byKey(syncKey)), loadingSync);
    });

    for (final (scope, title) in [
      (DriveScope.all, 'Your drives'),
      (DriveScope.public, 'Public drives'),
      (DriveScope.private, 'Private drives'),
      (DriveScope.sharedWithMe, 'Shared drives'),
      (DriveScope.hidden, 'Hidden'),
    ]) {
      testWidgets('is named for the scope: $title', (tester) async {
        await pumpBody(
          tester,
          DrivesListLoaded(drives: [drive('a')], scope: scope),
        );

        expect(
          find.descendant(
            of: find.byType(ListPageTitleRow),
            matching: find.text(title),
          ),
          findsOneWidget,
        );
      });
    }

    testWidgets('names the scope before the list has loaded', (tester) async {
      await pumpBody(
        tester,
        const DrivesListLoading(),
        scope: DriveScope.sharedWithMe,
      );

      expect(find.text('Shared drives'), findsOneWidget);
    });
  });

  group('the loading card', () {
    testWidgets('has the table\'s edges, not 16 px inside them',
        (tester) async {
      await pumpBody(tester, const DrivesListLoading());
      final row = tester.getRect(find.byType(ListPageTitleRow));
      final card = tester.getRect(
        find
            .ancestor(
              of: find.text('Loading your drives...'),
              matching: find.byType(Container),
            )
            .last,
      );

      expect(card.left, row.left);
      expect(card.right, row.right);
    });
  });

  group('an empty scope', () {
    testWidgets('is the design system\'s empty state, with an icon',
        (tester) async {
      await pumpBody(
        tester,
        const DrivesListLoaded(drives: [], scope: DriveScope.public),
      );

      expect(find.byType(ArDriveEmptyState), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ArDriveEmptyState),
          matching: find.byIcon(DriveScopeRail.iconFor(DriveScope.public)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Hidden says how a drive gets there', (tester) async {
      await pumpBody(
        tester,
        const DrivesListLoaded(drives: [], scope: DriveScope.hidden),
      );

      expect(find.text('No hidden drives'), findsOneWidget);
      expect(find.text('Drives you hide appear here.'), findsOneWidget);
      expect(find.textContaining('attach'), findsNothing,
          reason: 'Hidden is not about shared drives');
    });

    testWidgets('Your drives with every drive hidden points to Hidden',
        (tester) async {
      await pumpBody(
        tester,
        const DrivesListLoaded(
          drives: [],
          counts: DriveScopeCounts({DriveScope.hidden: 3}),
        ),
      );

      expect(find.text('All your drives are hidden'), findsOneWidget);
      expect(find.text('Find them under Hidden.'), findsOneWidget);
      expect(find.textContaining('attach'), findsNothing);
    });

    testWidgets('Shared offers Attach drive as a secondary button',
        (tester) async {
      await pumpBody(
        tester,
        const DrivesListLoaded(drives: [], scope: DriveScope.sharedWithMe),
      );

      final attach = tester.widget<ArDriveButtonNew>(
        find.widgetWithText(ArDriveButtonNew, 'Attach drive'),
      );
      expect(attach.variant, isNot(ButtonVariant.primary),
          reason: 'the sidebar\'s New is the view\'s one primary');
      expect(attach.maxWidth, isNull, reason: 'a button is sized to its label');
    });

    testWidgets('keeps a 16 px gutter on a phone', (tester) async {
      await pumpBody(
        tester,
        const DrivesListLoaded(drives: [], scope: DriveScope.sharedWithMe),
        width: 390,
      );

      final text = tester.getRect(
        find.text('No drives shared with you'),
      );
      expect(text.left, greaterThanOrEqualTo(16));
      expect(text.right, lessThanOrEqualTo(390 - 16));
      expect(tester.takeException(), isNull);
    });
  });

  group('one primary per view', () {
    testWidgets('could not be read offers Try again, not in red',
        (tester) async {
      await pumpBody(tester, DrivesListUnavailable());

      final tryAgain = tester.widget<ArDriveButtonNew>(
        find.widgetWithText(ArDriveButtonNew, 'Try again'),
      );
      expect(tryAgain.variant, isNot(ButtonVariant.primary));
    });
  });

  Future<void> pumpAlone(WidgetTester tester, Widget child) =>
      tester.pumpWidget(
        ArDriveTheme(
          themeData: lightTheme(),
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: 600, child: child),
              ),
            ),
          ),
        ),
      );

  group('the sidebar nav', () {
    testWidgets('a row is the 40 px touch target', (tester) async {
      await pumpAlone(
        tester,
        DriveNavRow(
          icon: Icons.public_outlined,
          label: 'Public drives',
          count: 3,
          isCurrent: true,
          onTap: () {},
        ),
      );

      // The row itself, the part that lights up, inside the hover padding.
      final row = find
          .descendant(
            of: find.byType(DriveNavRow),
            matching: find.byType(GestureDetector),
          )
          .first;
      expect(tester.getSize(row).height, DriveNavRow.navRowHeight);
      expect(DriveNavRow.navRowHeight, 40);
    });
  });

  group('a table row', () {
    testWidgets('is the menu target tall even without a menu', (tester) async {
      await pumpAlone(
        tester,
        ListTableRow(
          semanticLabel: 'row',
          onOpen: () {},
          showsColumns: true,
          child: const Text('name'),
        ),
      );

      expect(
        tester.getSize(find.byType(ListTableRow)).height,
        listMenuTapTarget,
      );
    });
  });
}

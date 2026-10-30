import 'package:ardrive/drives_list/domain/drive_list_item.dart';
import 'package:ardrive/drives_list/presentation/drives_list_cubit.dart';
import 'package:ardrive/drives_list/presentation/drives_list_page.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a returning reader is told, and where.
///
/// Everything on this page comes from the local database, which is what makes
/// it instant and also what makes it silently old. Each drive says so in its
/// own row, only when the network has confirmed it: there is no banner above
/// the table, which came and went with a tick or a sync and moved every row
/// under the pointer when it did.
void main() {
  DriveListItem drive(
    String id, {
    bool hasUnreadChanges = false,
    bool isSyncing = false,
    bool lastSyncFailed = false,
  }) =>
      DriveListItem(
        id: id,
        name: id,
        isPrivate: false,
        isSharedWithMe: false,
        isHidden: false,
        dateCreated: DateTime(2026, 3, 4),
        hasBeenWalked: true,
        hasUnreadChanges: hasUnreadChanges,
        fileCount: 12,
        totalSize: 4096,
        lastSyncedAt: DateTime(2026, 3, 1),
        isSyncing: isSyncing,
        lastSyncFailed: lastSyncFailed,
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
          home: Scaffold(body: child),
        ),
      );

  Future<void> pump(
    WidgetTester tester,
    DrivesListLoaded state, {
    Size size = const Size(1200, 900),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      host(
        DrivesListBody(
          state: state,
          onOpenDrive: (_) {},
          onTryAgain: () {},
        ),
      ),
    );
  }

  testWidgets('a changed drive says so in its own row', (tester) async {
    await pump(
      tester,
      DrivesListLoaded(drives: [
        drive('a', hasUnreadChanges: true),
        drive('b', hasUnreadChanges: true),
        drive('c'),
      ]),
    );

    expect(find.textContaining(', changed since'), findsNWidgets(2));
    // The time stays, so the column still says when, and sorts by it.
    expect(find.textContaining(RegExp(r'^Synced .+, changed since$')),
        findsNWidgets(2));
  });

  testWidgets('and nothing above the table says it again', (tester) async {
    await pump(
      tester,
      DrivesListLoaded(drives: [
        drive('a', hasUnreadChanges: true),
        drive('b', lastSyncFailed: true),
      ]),
    );

    expect(find.textContaining('have changed since'), findsNothing);
    expect(find.textContaining('has changed since'), findsNothing);
    expect(find.textContaining('could not be read'), findsNothing);
    expect(find.textContaining('Sync th'), findsNothing,
        reason: 'the split button is the page\'s one sync control');
    expect(find.byType(ArDriveButtonNew), findsNothing);
  });

  testWidgets('says nothing when every drive is current', (tester) async {
    await pump(tester, DrivesListLoaded(drives: [drive('a'), drive('b')]));

    expect(find.textContaining(', changed since'), findsNothing);
  });

  testWidgets('a drive being synced says that instead', (tester) async {
    await pump(
      tester,
      DrivesListLoaded(drives: [
        drive('a', hasUnreadChanges: true, isSyncing: true),
      ]),
    );

    expect(find.textContaining(', changed since'), findsNothing);
    expect(find.text('Syncing...'), findsOneWidget);
  });

  testWidgets('and a drive whose last sync failed says that', (tester) async {
    await pump(
      tester,
      DrivesListLoaded(drives: [
        drive('a', hasUnreadChanges: true, lastSyncFailed: true),
      ]),
    );

    expect(find.text('Last sync failed'), findsOneWidget);
    expect(find.textContaining(', changed since'), findsNothing);
  });

  /// The jump this used to cause: the banner left on the first tick or the
  /// start of a sync, every row moved up under the pointer, and the next
  /// click landed on a different drive.
  testWidgets('the table does not move when drives change, are ticked or sync',
      (tester) async {
    await pump(tester, DrivesListLoaded(drives: [drive('a'), drive('b')]));
    final before = tester.getTopLeft(find.text('Name'));

    for (final state in [
      DrivesListLoaded(drives: [
        drive('a', hasUnreadChanges: true),
        drive('b', lastSyncFailed: true),
      ]),
      DrivesListLoaded(
        drives: [drive('a', hasUnreadChanges: true), drive('b')],
        selected: const {'a'},
      ),
      DrivesListLoaded(drives: [
        drive('a', hasUnreadChanges: true, isSyncing: true),
        drive('b', isSyncing: true),
      ]),
    ]) {
      await pump(tester, state);
      expect(tester.getTopLeft(find.text('Name')), before);
    }
  });

  testWidgets('says the same thing on a phone, without overflowing',
      (tester) async {
    const phone = Size(375, 667);
    await pump(
      tester,
      DrivesListLoaded(drives: [
        drive('a', hasUnreadChanges: true),
        drive('b', hasUnreadChanges: true),
      ]),
      size: phone,
    );

    expect(find.textContaining(', changed since'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    for (var i = 0; i < 2; i++) {
      final rect = tester.getRect(find.textContaining(', changed since').at(i));
      expect(rect.right, lessThanOrEqualTo(phone.width));
    }
  });

  testWidgets("a new account's half-made first drive is not listed",
      (tester) async {
    await tester.pumpWidget(
      host(
        DrivesListBody(
          state: DrivesListLoaded(drives: [drive('my-files')]),
          onOpenDrive: (_) {},
          onTryAgain: () {},
          settingUpFirstDrive: true,
          buildEmpty: (_) => const Text('Setting up My files'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Setting up My files'), findsOneWidget);
    expect(find.text('my-files'), findsNothing);
  });
}

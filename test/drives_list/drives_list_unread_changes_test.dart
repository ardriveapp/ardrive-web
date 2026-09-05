import 'package:ardrive/drives_list/domain/drive_list_item.dart';
import 'package:ardrive/drives_list/presentation/drives_list_cubit.dart';
import 'package:ardrive/drives_list/presentation/drives_list_page.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a returning reader is told.
///
/// Everything on this page comes from the local database, which is what makes
/// it instant and also what makes it silently old: a reader who closed the tab
/// on Tuesday sees Tuesday's file counts drawn with exactly the confidence of
/// current ones. The notice under test is the only thing that says otherwise,
/// and it is only ever shown when the network has confirmed there is something
/// to say.
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
    VoidCallback? onSyncChanged,
    VoidCallback? onRetryFailed,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      host(
        DrivesListBody(
          state: state,
          onOpenDrive: (_) {},
          onTryAgain: () {},
          onSyncAllDrives: () {},
          onSyncChanged: onSyncChanged ?? () {},
          onRetryFailed: onRetryFailed,
        ),
      ),
    );
  }

  testWidgets('names how many drives moved on, and offers only those',
      (tester) async {
    await pump(
      tester,
      DrivesListLoaded(drives: [
        drive('a', hasUnreadChanges: true),
        drive('b', hasUnreadChanges: true),
        drive('c'),
      ]),
    );

    expect(
      find.text('2 drives have changed since they were last read'),
      findsOneWidget,
    );
    // The button names the same number the sentence does. A reader who is told
    // two and offered "Sync All Drives" has been told two different things.
    expect(find.text('Sync those 2'), findsOneWidget);
  });

  testWidgets('says nothing when every drive is current', (tester) async {
    await pump(tester, DrivesListLoaded(drives: [drive('a'), drive('b')]));

    expect(find.textContaining('have changed since'), findsNothing);
  });

  testWidgets('syncs the drives it named and nothing else', (tester) async {
    var pressed = 0;
    await pump(
      tester,
      DrivesListLoaded(drives: [
        drive('a', hasUnreadChanges: true),
        drive('b'),
      ]),
      onSyncChanged: () => pressed++,
    );

    await tester.tap(find.text('Sync that drive'));
    await tester.pump();

    expect(pressed, 1);
  });

  /// The offer is only an offer while it can be taken - the same rule the
  /// never-synced card follows one block up.
  testWidgets('withdraws itself while a sync is running', (tester) async {
    await pump(
      tester,
      DrivesListLoaded(drives: [
        drive('a', hasUnreadChanges: true, isSyncing: true),
      ]),
    );

    expect(find.textContaining('have changed since'), findsNothing);
    expect(find.textContaining('has changed since'), findsNothing);
  });

  /// Two red-adjacent offers of different scopes on one screen is the reader
  /// having to work out which one they meant, and they have just said which by
  /// ticking rows.
  testWidgets('withdraws itself while rows are ticked', (tester) async {
    await pump(
      tester,
      DrivesListLoaded(
        drives: [drive('a', hasUnreadChanges: true)],
        selected: const {'a'},
      ),
    );

    expect(find.textContaining('has changed since'), findsNothing);
  });

  /// A drive that could not be read at all is worse news than one that is
  /// merely behind, and the two notices say different things about different
  /// drives - so both stand.
  testWidgets('stands alongside a failure notice', (tester) async {
    await pump(
      tester,
      DrivesListLoaded(drives: [
        drive('a', hasUnreadChanges: true),
        drive('b', lastSyncFailed: true),
      ]),
      onRetryFailed: () {},
    );

    expect(find.text('1 drive has changed since it was last read'),
        findsOneWidget);
    expect(find.textContaining('could not be read'), findsOneWidget);
  });
}

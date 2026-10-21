import 'dart:io';

import 'package:ardrive/drives_list/domain/drive_list_item.dart';
import 'package:ardrive/drives_list/presentation/drive_list_row.dart';
import 'package:ardrive/drives_list/presentation/drives_list_cubit.dart';
import 'package:ardrive/drives_list/presentation/drives_list_page.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The card a first login lands on.
///
/// It is words only. It used to carry a red "Sync all drives" of its own, with
/// a measured breakpoint deciding whether that button sat beside the words or
/// under them - and below it, at some widths and text scales, it stretched to
/// a full-width slab. The page's split sync button, right above the card, now
/// reads "Sync all drives" in red for as long as the card is shown, so the
/// card says why and the button is how.
void main() {
  const title = 'Nothing has been synced yet';
  const description = 'Sync your drives to see their files and folders.';
  const syncingTitle = 'Fetching your drives';

  /// The real face, loaded from the design system's own asset.
  ///
  /// Without this every layout below is taken in the test font, whose glyphs
  /// are a square em each - an overflow check that has nothing to do with what
  /// a user sees.
  ///
  /// Loaded here rather than inside a test: `testWidgets` runs in a fake-async
  /// zone where a real file read never completes, so the same code in a test
  /// body hangs rather than measuring anything.
  setUpAll(() async {
    // The title is drawn semi-bold, so that is the face measured.
    final bytes = await File(
      'packages/ardrive_ui/assets/fonts/Wavehaus-95SemiBold.otf',
    ).readAsBytes();

    // The family a `package:` TextStyle actually resolves to.
    final loader = FontLoader('packages/ardrive_ui/Wavehaus')
      ..addFont(
        Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
      );

    await loader.load();
  });

  DriveListItem unwalked(String id, {bool isSyncing = false}) => DriveListItem(
        id: id,
        name: id,
        isPrivate: false,
        isSharedWithMe: false,
        isHidden: false,
        dateCreated: DateTime(2026, 3, 4),
        hasBeenWalked: false,
        fileCount: null,
        totalSize: null,
        lastSyncedAt: null,
        isSyncing: isSyncing,
        lastSyncFailed: false,
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

  /// Renders the list - card included - on a surface exactly [width] wide.
  ///
  /// The card's own width is asserted afterwards rather than assumed: a
  /// surface size that is silently clamped renders a different width than the
  /// one under test, and a layout test that never looks has proved nothing.
  Future<Size> pumpAt(
    WidgetTester tester,
    double width, {
    bool isSyncing = false,
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: DrivesListBody(
              state: DrivesListLoaded(
                drives: [unwalked('a', isSyncing: isSyncing)],
              ),
              onOpenDrive: (_) {},
              onTryAgain: () {},
            ),
          ),
        ),
      ),
    );

    // The card is the decorated box the title sits inside.
    final card = find.ancestor(
      of: find.text(isSyncing ? syncingTitle : title),
      matching: find.byType(Container),
    );

    final size = tester.getSize(card.first);

    // 16px of page padding either side of the card, and the list itself is
    // capped - so this is what a surface of this width actually gives it.
    final expected =
        (width < driveListMaxContentWidth ? width : driveListMaxContentWidth) -
            32;

    expect(size.width, expected,
        reason: 'the surface did not lay out at the width under test, so '
            'nothing below is measuring what it claims to');

    return size;
  }

  group('the card says which of the two it is', () {
    // The offer and the strip are on one screen. While a sync ran, this card
    // went on saying "their contents have not been fetched yet. Sync them all
    // now" beside a strip reporting "Found 340 items so far..." and above the
    // very button it names, disabled. Three surfaces, two of them wrong.
    testWidgets('offers the sync while there is one to offer', (tester) async {
      await pumpAt(tester, 1000);

      expect(find.text(title), findsOneWidget);
      expect(find.text(description), findsOneWidget);
    });

    testWidgets('and reports the one already running instead', (tester) async {
      await pumpAt(tester, 1000, isSyncing: true);

      expect(find.text(syncingTitle), findsOneWidget);
      expect(find.text(title), findsNothing,
          reason: 'the contents are being fetched right now, so "have not '
              'been fetched yet" is not true');
      expect(find.text(description), findsNothing);
      expect(
        find.textContaining('Sync them all now'),
        findsNothing,
        reason: 'it names an action it has just drawn as unavailable',
      );
    });
  });

  group('the reader\'s text scale', () {
    testWidgets('takes the drives list off columns before it clips them',
        (tester) async {
      // The breakpoint used to be pure pixels, so at a large text scale the
      // page kept five columns and ellipsized the values inside them - and a
      // count cut mid-digit still reads as a count.
      const widest = driveListMaxContentWidth;

      expect(driveListShowsColumns(widest, textScale: 1.0), isTrue,
          reason: 'precondition: the widest list draws columns at 1.0');
      expect(
        driveListShowsColumns(widest, textScale: 2.0),
        isFalse,
        reason: 'at 2.0 five columns of text do not fit any width this page '
            'allows, so the rows have to stack rather than truncate',
      );
      expect(
        driveListShowsColumns(600, textScale: 1.0),
        driveListShowsColumns(600 * 2, textScale: 2.0),
        reason: 'the breakpoint is a measurement of text, so twice the text '
            'in twice the width is the same decision',
      );
    });
  });

  group('the card', () {
    testWidgets('does not overflow on a 320px phone', (tester) async {
      await pumpAt(tester, 320);

      expect(tester.takeException(), isNull);
    });

    testWidgets('nor at twice the text size', (tester) async {
      await pumpAt(tester, 320, textScale: 2);

      expect(find.text(title), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('carries no button of its own, at any width', (tester) async {
      for (final width in [320.0, 700.0, 1200.0]) {
        await pumpAt(tester, width);

        expect(find.byType(ArDriveButtonNew), findsNothing,
            reason: 'the page\'s sync button is the one place sync lives '
                '(at ${width.toInt()}px)');
      }
    });
  });
}

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

/// The one card this page offers, and the only breakpoint it owns.
///
/// The card is two columns - words on the left, the one action on the right -
/// wherever two columns fit, and stacked only where they genuinely do not.
/// The width that separates the two is measured off the type the card is drawn
/// in, in the face it is drawn in, rather than picked: this feature has
/// already shipped a breakpoint chosen by eye twice, and both times it clipped
/// something at a band of widths nobody had rendered.
void main() {
  const title = 'Nothing has been synced yet';

  /// The real face, loaded from the design system's own asset.
  ///
  /// Without this every measurement below is taken in the test font, whose
  /// glyphs are a square em each - a "measurement" that has nothing to do with
  /// what a user sees and would put the breakpoint hundreds of pixels out.
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

  DriveListItem unwalked(String id) => DriveListItem(
        id: id,
        name: id,
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
          home: Scaffold(body: child),
        ),
      );

  /// Renders the list - card included - on a surface exactly [width] wide.
  ///
  /// The card's own width is asserted afterwards rather than assumed: a
  /// surface size that is silently clamped renders a different width than the
  /// one under test, and a layout test that never looks has proved nothing.
  Future<Size> pumpAt(WidgetTester tester, double width) async {
    await tester.binding.setSurfaceSize(Size(width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      host(
        DrivesListBody(
          state: DrivesListLoaded(drives: [unwalked('a')]),
          onOpenDrive: (_) {},
          onTryAgain: () {},
          onSyncAllDrives: () {},
        ),
      ),
    );

    // The card is the decorated box the title sits inside.
    final card = find.ancestor(
      of: find.text(title),
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

  Rect rectOf(WidgetTester tester, Finder finder) =>
      tester.getRect(finder.first);

  /// The card's text column - the title and the sentence under it, together.
  final wordsColumn =
      find.ancestor(of: find.text(title), matching: find.byType(Column)).first;

  group('the breakpoint', () {
    testWidgets('is at least the width the title actually measures',
        (tester) async {
      final measured = <double>[];

      // Both typographies, because which one is used is decided on the screen
      // width and the card can be two columns under either: the desktop face
      // is a point larger, and the constant has to clear the larger of them.
      for (final screenWidth in [400.0, 1200.0]) {
        await tester.binding.setSurfaceSize(Size(screenWidth, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        late TextStyle style;
        await tester.pumpWidget(
          host(
            Builder(
              builder: (context) {
                style = ArDriveTypographyNew.of(context).paragraphNormal(
                  fontWeight: ArFontWeight.semiBold,
                );

                return const SizedBox.shrink();
              },
            ),
          ),
        );

        final painter = TextPainter(
          text: TextSpan(text: title, style: style),
          textDirection: TextDirection.ltr,
        )..layout();

        measured.add(painter.width);
      }

      final widest = measured.reduce((a, b) => a > b ? a : b);

      expect(
        driveListSyncPromptTextMinimum,
        greaterThanOrEqualTo(widest),
        reason: 'below this the card\'s own title wraps, and two columns stop '
            'being a heading beside a button. Measured: $measured',
      );

      // And it is a measurement, not a round number well clear of one: a
      // minimum with 40px of slack in it has stopped being measured.
      expect(
        driveListSyncPromptTextMinimum,
        lessThan(widest + 40),
        reason: 'the constant has drifted away from what it measures. '
            'Measured: $measured',
      );
    });

    testWidgets('draws two columns at exactly the width it names',
        (tester) async {
      // The narrowest card the rule admits, plus the page padding either side.
      const surface = driveListSyncPromptTextMinimum + 16 + 180 + 32 + 32;

      expect(driveListSyncPromptShowsColumns(surface - 32), isTrue);

      await pumpAt(tester, surface);

      // The whole text column, not just its first line: the description wraps
      // underneath the title, and a button centred against the column sits
      // below the title's own bottom edge while still being beside the words.
      final words = rectOf(tester, wordsColumn);
      final button = rectOf(tester, find.byType(ArDriveButtonNew));

      expect(button.left, greaterThanOrEqualTo(words.right),
          reason: 'the button is meant to be the second column, not the '
              'second row');
      expect(button.top, lessThan(words.bottom),
          reason: 'a button that starts below the words is stacked, whatever '
              'its horizontal position');
      expect(button.bottom, greaterThan(words.top));
      expect(tester.takeException(), isNull);
    });

    testWidgets('stacks one pixel below it', (tester) async {
      const surface = driveListSyncPromptTextMinimum + 16 + 180 + 32 + 32 - 1;

      expect(driveListSyncPromptShowsColumns(surface - 32), isFalse);

      await pumpAt(tester, surface);

      final words = rectOf(tester, wordsColumn);
      final button = rectOf(tester, find.byType(ArDriveButtonNew));

      expect(button.top, greaterThanOrEqualTo(words.bottom),
          reason: 'two columns do not fit here, so the card has to stack');
      expect(tester.takeException(), isNull);
    });
  });

  group('the card', () {
    testWidgets('does not overflow on a 320px phone', (tester) async {
      await pumpAt(tester, 320);

      expect(tester.takeException(), isNull);
    });

    testWidgets('never gives the button the whole width, stacked or not',
        (tester) async {
      for (final width in [320.0, 700.0, 1200.0]) {
        final card = await pumpAt(tester, width);
        final button = rectOf(tester, find.byType(ArDriveButtonNew));

        expect(button.width, lessThan(card.width - 32),
            reason: 'a full-width slab of primary colour on the one screen '
                'whose message is "nothing is wrong yet" reads as an alarm '
                '(at ${width.toInt()}px)');
      }
    });
  });
}

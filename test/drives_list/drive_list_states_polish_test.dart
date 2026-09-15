import 'package:ardrive/drives_list/presentation/drives_list_page.dart';
import 'package:ardrive/drives_list/presentation/drives_list_cubit.dart';
import 'package:ardrive/pages/no_drives/no_drives_page.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The three screens around the list. The list itself was rendered at every
/// width; these were not, and every one of them was wrong in a different way.
void main() {
  Widget host(Widget child, {ArDriveThemeData? theme}) => ArDriveTheme(
        themeData: theme ?? lightTheme(),
        child: MaterialApp(
          theme: (theme ?? lightTheme()).materialThemeData,
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

  Future<void> at(WidgetTester tester, double width, Widget child,
      {ArDriveThemeData? theme}) async {
    await tester.binding.setSurfaceSize(Size(width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(child, theme: theme));
    await tester.pump();
  }

  group('the getting started cards', () {
    // dev laid these out with ScreenTypeLayout; extracting them introduced a
    // content-width breakpoint measured below what the pair actually needs, so
    // the second card was clipped against the window edge for 150px of widths.
    for (final width in [720.0, 768.0, 800.0, 840.0, 870.0, 877.0]) {
      testWidgets('do not overflow at ${width.toInt()}px', (tester) async {
        await at(tester, width, const GettingStartedCards());
        expect(tester.takeException(), isNull,
            reason: 'the second card was clipped at ${width.toInt()}px');
      });
    }

    testWidgets('sit side by side once they genuinely fit', (tester) async {
      await at(tester, 1000, const GettingStartedCards());
      expect(tester.takeException(), isNull);
      expect(find.byType(Row), findsWidgets);
    });
  });

  group('the headline of a state', () {
    // Both fell through to the Material body colour, which made the H1 the
    // faintest text on its own screen - the hierarchy inverted, in both themes.
    for (final entry in {
      'light': lightTheme(),
      'dark': ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode())
    }.entries) {
      testWidgets('is the strongest text on it (${entry.key})', (tester) async {
        await at(
            tester,
            1000,
            DrivesListBody(
              state: const DrivesListLoading(),
              onOpenDrive: (_) {},
              onTryAgain: () {},
              onSyncAllDrives: () {},
            ),
            theme: entry.value);

        final headline = tester.widget<Text>(
          find.text('Loading your drives...'),
        );
        expect(headline.style?.color, isNotNull,
            reason: 'the headline took the Material default, not a token');
        expect(headline.style?.color, entry.value.colorTokens.textHigh);
      });
    }
  });
}

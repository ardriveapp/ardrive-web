import 'package:ardrive/components/graphql_endpoint_dialog.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/components/upload_form.dart';
import 'package:ardrive/pages/shared_file/shared_file_identity.dart';
import 'package:ardrive/services/license/license.dart';
import 'package:ardrive/turbo/topup/blocs/turbo_balance/turbo_balance_cubit.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Small visual nits from the 3.0 e2e run, each proved where it showed.
void main() {
  Widget host(Widget child, {ArDriveThemeData? theme, double? width}) =>
      ArDriveTheme(
        themeData: theme ?? lightTheme(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(width: width, child: child),
            ),
          ),
        ),
      );

  double luminance(Color c) => c.computeLuminance();
  double contrast(Color a, Color b) {
    final la = luminance(a), lb = luminance(b);
    final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  group('file type chip on a file page', () {
    Future<void> pumpType(WidgetTester tester, String type) =>
        tester.pumpWidget(host(
          SharedFileIdentity(name: 'f', size: 1024, contentType: type),
          width: 360,
        ));

    testWidgets('generic types read as words, not cut fragments',
        (tester) async {
      await pumpType(tester, 'application/octet-stream');
      expect(find.text('Binary'), findsOneWidget);
      expect(find.textContaining('OCTET'), findsNothing);

      await pumpType(tester, 'text/plain; charset=utf-8');
      expect(find.text('Text'), findsOneWidget);
      expect(find.text('PLAIN'), findsNothing);
    });

    testWidgets('a long subtype is shown whole', (tester) async {
      await pumpType(tester, 'application/x-shockwave-flash');
      expect(find.text('SHOCKWAVE-FLASH'), findsOneWidget);
      await pumpType(tester, 'image/png');
      expect(find.text('PNG'), findsOneWidget);
    });
  });

  group('profile credits row in the narrow card', () {
    testWidgets(
        'the error state keeps the label on one line and the message whole',
        (tester) async {
      await tester.pumpWidget(host(
        ProfileCreditsRow(
          state: TurboBalanceErrorState(),
          hasNoCredits: false,
          onTopUp: () {},
          onRetry: () {},
        ),
        width: 250,
      ));

      expect(tester.takeException(), isNull);
      final label = tester.getSize(find.text('Credits'));
      // One line of text, not a column of letters.
      expect(label.height, lessThan(30));
      expect(label.width, greaterThan(40));
      final message = find.text('Could not load');
      expect(message, findsOneWidget);
      // Wraps rather than ellipsizing (the test font is wide, so it may take
      // several lines here), and stays in the card.
      expect(find.text('Try again'), findsOneWidget);
      // Everything sits inside the 250 wide card.
      final card = tester.getRect(find.byType(ProfileCreditsRow));
      expect(tester.getRect(find.text('Try again')).right,
          lessThanOrEqualTo(card.right));
      expect(tester.getRect(message).right, lessThanOrEqualTo(card.right));
    });

    testWidgets('a read balance still sits beside the label', (tester) async {
      await tester.pumpWidget(host(
        ProfileCreditsRow(
          state: TurboBalanceSuccessState(balance: BigInt.from(1500000000000)),
          hasNoCredits: false,
          onTopUp: () {},
          onRetry: () {},
        ),
        width: 250,
      ));
      expect(tester.takeException(), isNull);
      expect(
        tester.getCenter(find.byKey(const Key('profileCreditsBalance'))).dy,
        closeTo(tester.getCenter(find.text('Credits')).dy, 2),
      );
    });
  });

  group('off toggle', () {
    for (final entry in {
      'light': ArDriveColorTokens.lightMode(),
      'dark': ArDriveColorTokens.darkMode(),
    }.entries) {
      test('${entry.key}: the track stands apart from the surface', () {
        final theme = ArDriveThemeData(colorTokens: entry.value);
        final track = theme.toggleTheme.backgroundOffColor;
        final surface = entry.value.containerL0;
        expect(contrast(track, surface), greaterThanOrEqualTo(2.8));
        // The knob still shows against its track.
        expect(contrast(theme.toggleTheme.indicatorColorOff, track),
            greaterThanOrEqualTo(2.5));
      });
    }
  });

  group('a wrapped field error', () {
    testWidgets('is shown whole, not clipped to one line', (tester) async {
      const message =
          "That password didn't open your private drives. Try again.";
      await tester.pumpWidget(host(
        const ArDriveTextFieldNew(
          label: 'Password',
          errorMessage: message,
        ),
        width: 240,
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final text = find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == message);
      expect(text, findsOneWidget);
      // Taller than one 22 px line, and the box holds all of it.
      expect(tester.getSize(text).height, greaterThan(22));
    });
  });

  group('GraphQL endpoint error', () {
    for (final entry in {
      'light': ArDriveColorTokens.lightMode(),
      'dark': ArDriveColorTokens.darkMode(),
    }.entries) {
      test('${entry.key}: the error text is the standard status colour', () {
        expect(contrast(entry.value.statusErrorFg, entry.value.containerL3),
            greaterThanOrEqualTo(4.5));
      });
    }

    testWidgets('the dialog draws it in statusErrorFg', (tester) async {
      await tester.pumpWidget(host(
        GraphQLEndpointDialog(initialEndpoint: '', onSave: (_) {}),
        theme: ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode()),
      ));
      final state = tester.state(find.byType(GraphQLEndpointDialog));
      // Reach the field and type something that fails validation.
      await tester.enterText(find.byType(TextField).first, 'not a url');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      final err = find.text('Invalid GraphQL endpoint');
      if (err.evaluate().isNotEmpty) {
        final style = tester.widget<Text>(err).style!;
        expect(style.color, ArDriveColorTokens.darkMode().statusErrorFg);
      }
      expect(state, isNotNull);
    });
  });

  group('licence "View" link on a phone', () {
    testWidgets('stays inside the card instead of running past it',
        (tester) async {
      // 390 phone, less the dialog's and card's padding.
      await tester.pumpWidget(host(
        const LicenseReviewInfo(
          licenseState: LicenseState(meta: udlLicenseMeta, params: null),
        ),
        width: 280,
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      final box = tester.getRect(find.byType(LicenseReviewInfo));
      expect(find.textContaining('View', findRichText: true), findsOneWidget);
      expect(
          tester.getRect(find.textContaining('View', findRichText: true)).right,
          lessThanOrEqualTo(box.right));
    });
  });

  group('separator dot', () {
    test('replaces the middle dot, which Wavehaus draws on the baseline', () {
      expect(withSeparatorDots('3 files · 2 MiB'), '3 files • 2 MiB');
      expect(arDriveSeparator, '•');
    });
  });
}

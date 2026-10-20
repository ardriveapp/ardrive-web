import 'package:ardrive/components/copy_button.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
          home: Scaffold(body: Center(child: child)),
        ),
      );

  /// Answers the clipboard write the way the browser would: with the text
  /// taken, or refused.
  void clipboard(WidgetTester tester, {required bool Function() refuses}) {
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData' && refuses()) {
        throw PlatformException(
          code: 'copy_fail',
          message: 'Clipboard.setData failed',
        );
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
  }

  group('CopyButton', () {
    testWidgets('says the text was copied when the browser took it',
        (tester) async {
      clipboard(tester, refuses: () => false);
      await tester.pumpWidget(
        wrap(const CopyButton(text: 'a-link', child: Text('Copy link'))),
      );

      await tester.tap(find.text('Copy link'));
      await tester.pump();

      expect(find.text('Copied!'), findsOneWidget);
      expect(find.text("Couldn't copy"), findsNothing);

      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('says it could not copy when the browser refused',
        (tester) async {
      // A phone's browser refuses a write it does not count as the reader's
      // own, and the button said "Copied!" anyway.
      clipboard(tester, refuses: () => true);
      await tester.pumpWidget(
        wrap(const CopyButton(text: 'a-link', child: Text('Copy link'))),
      );

      await tester.tap(find.text('Copy link'));
      await tester.pump();

      expect(find.text("Couldn't copy"), findsOneWidget);
      expect(find.text('Copied!'), findsNothing);

      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('says so when a retry after a refusal works', (tester) async {
      var refuses = true;
      clipboard(tester, refuses: () => refuses);
      await tester.pumpWidget(
        wrap(const CopyButton(text: 'a-link', child: Text('Copy link'))),
      );

      await tester.tap(find.text('Copy link'));
      await tester.pump();
      expect(find.text("Couldn't copy"), findsOneWidget);

      refuses = false;
      await tester.tap(find.text('Copy link'));
      await tester.pump();

      expect(find.text('Copied!'), findsOneWidget);
      expect(find.text("Couldn't copy"), findsNothing);

      await tester.pump(const Duration(seconds: 2));
    });
  });
}

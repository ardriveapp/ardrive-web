import 'package:ardrive/authentication/login/views/modals/common.dart';
import 'package:ardrive/components/progress_dialog.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

/// The dialogs other dialogs lean on: the error and the wait. Both are the
/// standard dialog, drawn from the design system.
void main() {
  Widget app(Widget Function(BuildContext) open) => ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
          home: ChangeNotifierProvider<ActivityTracker>(
            create: (_) => ActivityTracker(),
            child: Scaffold(body: Builder(builder: open)),
          ),
        ),
      );

  group('the error dialog', () {
    Future<void> open(WidgetTester tester, {bool logs = false}) async {
      await tester.pumpWidget(app((context) => TextButton(
            onPressed: () => showErrorDialog(
              context: context,
              title: 'Drive not created',
              message: 'Check your connection and try again.',
              showShareLogsButton: logs,
            ),
            child: const Text('open'),
          )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('is the standard dialog with a quiet Close', (tester) async {
      await open(tester);

      expect(find.byType(ArDriveStandardModalNew), findsOneWidget);
      expect(find.text('Drive not created'), findsOneWidget);
      expect(find.text('Check your connection and try again.'), findsOneWidget);
      final close = tester.widget<ArDriveButtonNew>(
          find.widgetWithText(ArDriveButtonNew, 'Close'));
      // Closing does nothing, so it is never the red primary.
      expect(close.variant, ButtonVariant.secondary);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(ArDriveStandardModalNew), findsNothing);
    });

    testWidgets('can offer Copy logs, in the app\'s words', (tester) async {
      await open(tester, logs: true);

      final copy = tester.widget<ArDriveButtonNew>(
          find.widgetWithText(ArDriveButtonNew, 'Copy logs'));
      expect(copy.variant, ButtonVariant.primary);
      expect(find.text('Close'), findsOneWidget);
    });
  });

  testWidgets('a refused copy says so, and Copy logs can be pressed again',
      (tester) async {
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        throw PlatformException(code: 'denied');
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(app((context) => TextButton(
          onPressed: () => showErrorDialog(
            context: context,
            message: 'Something went wrong.',
            showShareLogsButton: true,
          ),
          child: const Text('open'),
        )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('Copy logs'));
      await Future.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    expect(find.text("Couldn't copy"), findsOneWidget);
    final copy = tester.widget<ArDriveButtonNew>(
        find.widgetWithText(ArDriveButtonNew, "Couldn't copy"));
    expect(copy.isDisabled, isFalse);
  });

  testWidgets('the wait is the design system spinner, not an animation file',
      (tester) async {
    await tester
        .pumpWidget(app((context) => const ProgressDialog(title: 'Renaming')));

    expect(find.byType(ArDriveSpinner), findsOneWidget);
    expect(find.byType(LottieBuilder), findsNothing);
    expect(find.text('Renaming'), findsOneWidget);
  });
}

import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/sync/presentation/full_resync_confirmation.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The full resync question: Cancel is the close action, so the X and Cancel
/// answer the same, and Full resync is the primary.
void main() {
  Future<bool?> ask(WidgetTester tester, Future<void> Function() answer) async {
    bool? result;
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ActivityTracker(),
        child: ArDriveTheme(
          themeData: lightTheme(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await confirmFullResync(
                  context,
                  const FullResyncScope.drive('My Drive'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await answer();
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('Cancel is secondary, and the X answers the same as Cancel',
      (tester) async {
    final result = await ask(tester, () async {
      expect(
        tester
            .widget<ArDriveButtonNew>(
                find.widgetWithText(ArDriveButtonNew, 'Cancel'))
            .variant,
        ButtonVariant.secondary,
      );
      // The corner X is there because Cancel only closes.
      expect(find.byType(ArDriveIcon), findsOneWidget);
      await tester.tap(find.byType(ArDriveIcon));
    });

    expect(result, isFalse);
  });

  testWidgets('the primary agrees', (tester) async {
    final result = await ask(tester, () async {
      final buttons = tester
          .widgetList<ArDriveButtonNew>(find.byType(ArDriveButtonNew))
          .toList();
      expect(buttons.first.text, 'Cancel');
      await tester.tap(find.byWidget(buttons.last));
    });

    expect(result, isTrue);
  });
}

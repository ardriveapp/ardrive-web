import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Forget all on this device" asks first; a single drive's Forget does not.
void main() {
  Future<bool?> open(WidgetTester tester, int count, String tap) async {
    bool? answer;
    await tester.pumpWidget(ArDriveTheme(
      themeData: lightTheme(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en', '')],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              answer = await showDialog<bool>(
                context: context,
                builder: (_) =>
                    Dialog(child: ForgetAllOnThisDeviceDialog(count: count)),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text("You'll need their passwords to open them again."),
        findsOneWidget);
    await tester.tap(find.text(tap));
    await tester.pumpAndSettle();
    return answer;
  }

  testWidgets('says how many, and Forget confirms', (tester) async {
    expect(await open(tester, 3, 'Forget'), isTrue);
  });

  testWidgets('Cancel forgets nothing', (tester) async {
    expect(await open(tester, 1, 'Cancel'), isFalse);
  });

  testWidgets('one drive is one drive', (tester) async {
    await tester.pumpWidget(ArDriveTheme(
      themeData: lightTheme(),
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en', '')],
        home: Scaffold(body: ForgetAllOnThisDeviceDialog(count: 1)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Forget 1 drive on this device?'), findsOneWidget);
  });
}

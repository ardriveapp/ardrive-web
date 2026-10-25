import 'package:ardrive/gar/presentation/widgets/gateway_input_modal.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Save looked ready before the gateway had been checked, and pressing it did
/// nothing at all.
void main() {
  Future<void> open(WidgetTester tester,
      {required void Function(String) onSave}) async {
    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: GatewayInputModal(
                initialGateway: 'https://turbo-gateway.com',
                onSave: onSave,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  ArDriveButtonNew saveButton(WidgetTester tester) => tester
      .widgetList<ArDriveButtonNew>(find.byType(ArDriveButtonNew))
      .firstWhere((button) => button.text == 'Save');

  testWidgets('Save is disabled until the gateway is checked', (tester) async {
    String? saved;
    await open(tester, onSave: (url) => saved = url);

    expect(find.text('Switch gateway'), findsOneWidget);
    expect(saveButton(tester).isDisabled, isTrue);

    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(saved, isNull);
  });

  testWidgets('emptying the URL leaves Save disabled', (tester) async {
    await open(tester, onSave: (_) {});

    await tester.enterText(find.byType(TextFormField), '');
    await tester.pump(const Duration(milliseconds: 600));

    expect(saveButton(tester).isDisabled, isTrue);
    expect(find.byType(ArDriveNotice), findsNothing);
  });
}

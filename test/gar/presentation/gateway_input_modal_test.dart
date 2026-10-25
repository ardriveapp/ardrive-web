import 'dart:async';

import 'package:ardrive/gar/presentation/widgets/gateway_input_modal.dart';
import 'package:ardrive/gar/utils/gateway_validator.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Save looked ready before the gateway had been checked, and pressing it did
/// nothing at all.
void main() {
  Future<void> open(
    WidgetTester tester, {
    required void Function(String) onSave,
    Future<GatewayValidationResult> Function(String url)? validate,
  }) async {
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
                validate: validate ?? GatewayValidator.validateGateway,
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

  const usable = GatewayValidationResult(
    isValid: true,
    isActive: true,
    isArweaveGateway: true,
    message: 'Gateway is ready.',
  );

  testWidgets('a checked gateway can be saved', (tester) async {
    String? saved;
    await open(
      tester,
      onSave: (url) => saved = url,
      validate: (_) async => usable,
    );

    await tester.enterText(find.byType(TextFormField), 'https://ar-io.dev');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(saveButton(tester).isDisabled, isFalse);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, 'https://ar-io.dev');
  });

  // A check that came back after the URL changed enabled Save for the new,
  // unchecked URL.
  testWidgets('a check for an earlier URL is dropped', (tester) async {
    final pending = <String, Completer<GatewayValidationResult>>{};
    await open(
      tester,
      onSave: (_) {},
      validate: (url) => (pending[url] = Completer()).future,
    );

    await tester.enterText(find.byType(TextFormField), 'https://ar-io.dev');
    await tester.pump(const Duration(milliseconds: 600));
    expect(pending.keys, ['https://ar-io.dev']);

    await tester.enterText(find.byType(TextFormField), 'https://nope.example');
    await tester.pump();
    pending['https://ar-io.dev']!.complete(usable);
    await tester.pump();

    expect(saveButton(tester).isDisabled, isTrue);
    expect(find.text('Gateway is ready.'), findsNothing);

    // Its own check, once it runs, is the one that counts.
    await tester.pump(const Duration(milliseconds: 600));
    pending['https://nope.example']!.complete(const GatewayValidationResult(
      isValid: false,
      isActive: false,
      isArweaveGateway: false,
      message: 'Not a gateway.',
    ));
    await tester.pump();
    expect(saveButton(tester).isDisabled, isTrue);
    expect(find.text('Not a gateway.'), findsWidgets);
  });
}

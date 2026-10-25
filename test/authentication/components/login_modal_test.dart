import 'package:ardrive/authentication/components/login_modal.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sign-in card was its own container copied from the dialog, without
/// its shadow and with a smaller close button. It is the dialog now.
void main() {
  Future<void> open(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const Center(
                  child: ArDriveLoginModal(
                    width: 450,
                    content: Text('Import wallet'),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('is the standard dialog, and its close button is named',
      (tester) async {
    await open(tester, const Size(1440, 900));

    expect(find.byType(ArDriveModalNew), findsOneWidget);
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Close'), findsOneWidget);
    handle.dispose();

    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Import wallet'), findsNothing);
  });

  testWidgets('keeps its content centred across its width', (tester) async {
    await open(tester, const Size(1440, 900));

    final card = tester.getRect(find.byType(ArDriveModalNew));
    final content = tester.getRect(find.text('Import wallet'));
    expect(card.width, 450);
    expect(content.center.dx, moreOrLessEquals(card.center.dx, epsilon: 1));
  });

  testWidgets('uses the phone padding on a phone', (tester) async {
    await open(tester, const Size(390, 844));

    final card = tester.getRect(find.byType(ArDriveModalNew));
    expect(card.width, lessThanOrEqualTo(390));
    expect(tester.takeException(), isNull);
  });
}

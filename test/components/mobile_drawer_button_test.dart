import 'package:ardrive/app_shell.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// The menu icon in the narrow header had no label, so a screen reader had
  /// no name to announce for it.
  testWidgets('the drawer button is a named button and opens the drawer',
      (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en', '')],
          home: Scaffold(
            drawer: Drawer(child: Text('Drawer content')),
            body: Center(child: MobileDrawerButton()),
          ),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.byType(MobileDrawerButton)),
      matchesSemantics(
        label: 'Show menu',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );

    tester.semantics.tap(find.semantics.byLabel('Show menu'));
    await tester.pumpAndSettle();

    expect(find.text('Drawer content'), findsOneWidget);

    handle.dispose();
  });
}

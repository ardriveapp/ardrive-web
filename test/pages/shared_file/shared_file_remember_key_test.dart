import 'package:ardrive/pages/shared_file/shared_file_locked_view.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Remember this key for this tab" on the locked gate: one Tab stop, one
/// focus ring, announced once. It was a focusable wrapper around a box that
/// became focusable itself, which made two stops for one checkbox.
void main() {
  late List<bool> changes;

  Future<void> pump(WidgetTester tester) async {
    changes = [];
    var remember = false;
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => SharedFileLockedView(
                controller: controller,
                onSubmit: (_) {},
                rememberKey: remember,
                onRememberChanged: (value) => setState(() {
                  changes.add(value);
                  remember = value;
                }),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('one Tab stop, which Space ticks and unticks', (tester) async {
    await pump(tester);

    // Every focus node Tab reaches on the way round that sits on the box or
    // its label: the wrapper and the box inside it were two.
    final label = tester.getRect(find.text('Remember this key for this tab'));
    final box = tester.getRect(find.byType(ArDriveCheckBox));
    final stops = <FocusNode>{};
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final node = FocusManager.instance.primaryFocus!;
      if (node.rect.overlaps(label) || node.rect.overlaps(box)) {
        stops.add(node);
      }
    }
    expect(stops, hasLength(1));

    // Focus the box and tick it twice.
    while (
        FocusManager.instance.primaryFocus?.debugLabel != 'ArDriveCheckBox') {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(changes, [true, false]);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'ArDriveCheckBox');
  });

  testWidgets('announced once, as a checkbox', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);

    expect(
      tester.getSemantics(find.byType(ArDriveCheckBox)),
      matchesSemantics(
        label: 'Remember this key for this tab',
        hasCheckedState: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
      ),
    );
    expect(find.bySemanticsLabel('Remember this key for this tab'),
        findsOneWidget);
    semantics.dispose();
  });
}

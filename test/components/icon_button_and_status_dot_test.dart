import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/file_icon.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en', '')],
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    );

void main() {
  /// The details panel's toolbar is a row of these. A screen reader read
  /// each one's name with nothing to say it could be pressed.
  testWidgets('an icon button is a button to a screen reader, named once',
      (tester) async {
    final handle = tester.ensureSemantics();
    var pressed = 0;

    await _pump(
      tester,
      ArDriveIconButton(
        icon: ArDriveIcons.share(),
        tooltip: 'Share file',
        onPressed: () => pressed++,
      ),
    );

    final node = tester.getSemantics(find.byType(ArDriveIconButton));
    expect(
      node,
      matchesSemantics(
        label: 'Share file',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );

    expect(node.label, 'Share file');
    tester.semantics.tap(find.semantics.byLabel('Share file'));
    expect(pressed, 1);

    handle.dispose();
  });

  /// The grid view draws a file's status with its own icon, and its dot had
  /// no tooltip where the table's did.
  testWidgets('the grid view says what a file status dot means',
      (tester) async {
    await _pump(
      tester,
      const ArDriveFileIcon(
        contentType: 'text/plain',
        fileStatus: TransactionStatus.pending,
      ),
    );

    expect(
      find.byTooltip(
        'Waiting to be mined on Arweave. This is checked for you until it is.',
      ),
      findsOneWidget,
    );
  });
}

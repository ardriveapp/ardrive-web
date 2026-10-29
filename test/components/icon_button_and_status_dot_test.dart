import 'dart:ui' as ui;

import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/file_icon.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

  /// The close button on the sign-in dialogs drew its X 6 px left of the
  /// middle of its hover highlight, on the web only: the icon font's
  /// metrics put every glyph's left edge at the side of its box. Drawn with
  /// the real font, which the rest of the suite never loads.
  testWidgets('an icon button draws its icon in the middle of the button',
      (tester) async {
    final loader = FontLoader('packages/ardrive_ui/ArDriveIcons')
      ..addFont(
        rootBundle.load('packages/ardrive_ui/assets/fonts/ArDriveIcons.ttf'),
      );
    await loader.load();

    final key = GlobalKey();
    await _pump(
      tester,
      RepaintBoundary(
        key: key,
        child: ArDriveIconButton(
          icon: ArDriveIcons.x(size: 24, color: const Color(0xFF000000)),
          tooltip: 'Close',
          onPressed: () {},
        ),
      ),
    );

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ink = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final rgba =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      var left = image.width;
      var right = -1;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          if (rgba.getUint8((y * image.width + x) * 4 + 3) > 0) {
            if (x < left) left = x;
            if (x > right) right = x;
          }
        }
      }
      final width = image.width;
      image.dispose();
      return (left: left, right: right, width: width);
    });

    expect(ink!.right, greaterThan(ink.left), reason: 'nothing was drawn');
    expect(
      (ink.left + ink.right + 1) / 2,
      moreOrLessEquals(ink.width / 2, epsilon: 1.0),
      reason: 'ink spans columns ${ink.left}-${ink.right} of ${ink.width}',
    );
  });
}

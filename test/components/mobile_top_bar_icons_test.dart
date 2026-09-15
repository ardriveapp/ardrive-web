import 'package:ardrive/app_shell.dart';
import 'package:ardrive/components/app_top_bar.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every control in the mobile bar is the same size as every other.
///
/// They were not: the drawer button was 20 while the hide toggle, the sync
/// indicator and the way home all took `ArDriveIcon`'s 24 - and the sync glyph
/// was 12 while a sync ran, so the one control the user watches during a sync
/// halved the moment it became busy.
void main() {
  /// The size of the glyph an `ArDriveIcon` renders. Null means it took the
  /// class default, which is what most of the bar does.
  double glyphSize(WidgetTester tester, Finder icon) =>
      tester.widget<ArDriveIcon>(icon).size ?? 24;

  testWidgets('the sync glyph does not change size when a sync starts',
      (tester) async {
    // Read from the constants the widgets use rather than by pumping the whole
    // shell: the two values are what the eye compares, and they are what
    // drifted apart.
    expect(
      syncGlyphSizeWhileSyncing,
      greaterThan(syncIndicatorSize / 2),
      reason: 'the glyph used to halve the moment the ring appeared',
    );
    // The ring is inset, so the glyph has to clear the inset and the stroke
    // on both sides rather than just the stroke.
    expect(
      syncIndicatorSize - syncRingInset * 2 - syncGlyphSizeWhileSyncing,
      greaterThanOrEqualTo(4),
      reason: 'the glyph has to sit inside the ring with clearance',
    );
  });

  testWidgets('an idle sync glyph is the bar size', (tester) async {
    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          home: Scaffold(
            body: ArDriveIcons.refresh(),
          ),
        ),
      ),
    );

    expect(glyphSize(tester, find.byType(ArDriveIcon)), mobileAppBarIconSize);
  });
}

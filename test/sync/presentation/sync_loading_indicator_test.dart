import 'package:ardrive/sync/presentation/sync_loading_indicator.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

/// One mark for "working", on every surface that waits on a sync.
///
/// There were three before, and they did not agree: a linear bar in the accent
/// on the drives list, one in `textHigh` in the explorer, and a ring in the top
/// bar - so the same wait read as a red bar on one screen and a white one on
/// the next.
void main() {
  Widget host(Widget child, {bool dark = false}) => ArDriveTheme(
        themeData: dark ? null : lightTheme(),
        child: MaterialApp(home: Scaffold(body: Center(child: child))),
      );

  testWidgets('is the plate stack, not a bar or a ring', (tester) async {
    await tester.pumpWidget(host(const SyncLoadingIndicator()));
    await tester.pump();

    expect(find.byType(LottieBuilder), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('draws at the size it is given, in both themes', (tester) async {
    for (final dark in [false, true]) {
      await tester.pumpWidget(
        host(const SyncLoadingIndicator(size: 56), dark: dark),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final box = tester.getSize(find.byType(LottieBuilder));
      expect(box.width, 56);
      expect(box.height, 56);
    }
  });

  testWidgets('says nothing to a screen reader, having nothing to say',
      (tester) async {
    // Decoration around a line of text that already reports the wait. A second
    // voice saying "loading" over it is noise.
    await tester.pumpWidget(host(const SyncLoadingIndicator()));
    await tester.pump();

    expect(
      find.ancestor(
        of: find.byType(LottieBuilder),
        matching: find.byType(ExcludeSemantics),
      ),
      findsWidgets,
    );
  });
}

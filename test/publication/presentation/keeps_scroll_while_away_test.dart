import 'package:ardrive/publication/presentation/publish/publish_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The look step's scroll, after the image chooser shows in its place and
/// Back returns to it.
void main() {
  Widget host(bool away, ScrollController controller) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: SingleChildScrollView(
              controller: controller,
              child: KeepsScrollWhileAway(
                away: away,
                child: Column(children: [
                  Offstage(
                    offstage: away,
                    child: const SizedBox(height: 2000),
                  ),
                  if (away) const SizedBox(height: 100),
                ]),
              ),
            ),
          ),
        ),
      );

  testWidgets('is where it was after the chooser', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(false, controller));
    controller.jumpTo(800);
    await tester.pump();

    await tester.pumpWidget(host(true, controller));
    await tester.pump();
    expect(controller.offset, 0, reason: 'clamped to the shorter chooser');

    await tester.pumpWidget(host(false, controller));
    await tester.pump();
    expect(controller.offset, 800);
  });
}

import 'package:ardrive/components/wallet_gradient_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const address = 'ZEs8xgsLswYQhW8x4ao6uqo8ULnTkc8gnbqaQ6Jm7Nw';

  Future<void> pumpAvatar(WidgetTester tester, {bool still = false}) =>
      tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: still),
            child: const Scaffold(
              body: Row(
                children: [
                  Text('Beside the avatar'),
                  WalletGradientAvatar(address: address, ringColor: Colors.red),
                ],
              ),
            ),
          ),
        ),
      );

  RenderObject avatarPainter(WidgetTester tester) => tester.renderObject(
        find.descendant(
          of: find.byType(WalletGradientAvatar),
          matching: find.byType(CustomPaint),
        ),
      );

  // The avatar is in the top bar of every signed-in page and breathes for
  // as long as it is there. On the HTML renderer, which phones get, a
  // repaint rebuilds the DOM of everything it covers.
  testWidgets('the breath repaints the avatar alone', (tester) async {
    await pumpAvatar(tester);
    await tester.pump(const Duration(milliseconds: 100));
    final beside = tester.renderObject(find.text('Beside the avatar'));

    final painted = <RenderObject>{};
    debugOnProfilePaint = painted.add;
    try {
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    } finally {
      debugOnProfilePaint = null;
    }
    expect(painted, contains(avatarPainter(tester)), reason: 'it breathes');
    expect(painted, isNot(contains(beside)));
    // The ring around it stands still too.
    expect(painted.whereType<RenderDecoratedBox>(), isEmpty);
  });

  // On the HTML renderer a picture of rectangles alone becomes a DOM element
  // per rectangle, made again on every frame. The cells go in paths, which
  // put the avatar on one canvas.
  testWidgets('the cells are drawn as paths', (tester) async {
    await pumpAvatar(tester);
    expect(
      avatarPainter(tester),
      paints
        ..rect()
        ..path()
        ..path(),
    );
    expect(avatarPainter(tester), isNot(paints..rect()..rect()));
  });

  testWidgets('under reduced motion it holds still', (tester) async {
    await pumpAvatar(tester, still: true);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.hasRunningAnimations, isFalse);
  });
}

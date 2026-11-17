import 'package:ardrive/pages/drive_detail/components/drive_detail_syncing_card.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _opacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(find.descendant(
        of: find.byType(DelayedReveal), matching: find.byType(AnimatedOpacity)))
    .opacity;

void main() {
  group('DelayedReveal', () {
    testWidgets('a short wait never shows the panel', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: DelayedReveal(immediate: false, child: Text('Opening')),
      ));
      expect(_opacity(tester), 0);
      await tester.pump(const Duration(milliseconds: 250));
      expect(_opacity(tester), 0);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a longer wait fades the panel in', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: DelayedReveal(immediate: false, child: Text('Opening')),
      ));
      await tester.pump(const Duration(milliseconds: 350));
      expect(_opacity(tester), 1);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Opening'), findsOneWidget);
    });

    testWidgets('a sync shows at once', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: DelayedReveal(immediate: true, child: Text('Syncing')),
      ));
      expect(_opacity(tester), 1);
    });

    testWidgets('a wait that turns into a sync shows at once', (tester) async {
      Widget build(bool immediate) => MaterialApp(
            home: DelayedReveal(
              immediate: immediate,
              child: const Text('x'),
            ),
          );
      await tester.pumpWidget(build(false));
      expect(_opacity(tester), 0);
      await tester.pumpWidget(build(true));
      expect(_opacity(tester), 1);
    });
  });

  group('ShellFade', () {
    testWidgets('crossfades between signed-out and signed-in', (tester) async {
      Widget build(bool out, String label) => MaterialApp(
            home: ShellFade(signedOutShell: out, child: Text(label)),
          );
      await tester.pumpWidget(build(true, 'login'));
      await tester.pumpWidget(build(false, 'app'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('login'), findsOneWidget);
      expect(find.text('app'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('login'), findsNothing);
      expect(find.text('app'), findsOneWidget);
    });

    testWidgets('moves inside the app do not crossfade', (tester) async {
      Widget build(String label) => MaterialApp(
            home: ShellFade(signedOutShell: false, child: Text(label)),
          );
      await tester.pumpWidget(build('a'));
      await tester.pumpWidget(build('b'));
      expect(find.text('a'), findsNothing);
      expect(find.text('b'), findsOneWidget);
    });
  });
}

import 'package:ardrive/pages/drive_detail/components/drive_detail_syncing_card.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _opacity(WidgetTester tester) => tester
    .widget<FadeTransition>(find.descendant(
        of: find.byType(DelayedReveal), matching: find.byType(FadeTransition)))
    .opacity
    .value;

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
      expect(_opacity(tester), lessThan(1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_opacity(tester), 1);
      expect(find.text('Opening'), findsOneWidget);
    });

    testWidgets('a sync shows at once', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: DelayedReveal(immediate: true, child: Text('Syncing')),
      ));
      expect(_opacity(tester), 1);
    });

    testWidgets('a sync starting mid-fade jumps to full without remounting',
        (tester) async {
      var created = 0;
      Widget build(bool immediate) => MaterialApp(
            home: DelayedReveal(
              immediate: immediate,
              child: _Mount(onCreate: () => created++),
            ),
          );
      await tester.pumpWidget(build(false));
      await tester.pump(const Duration(milliseconds: 320));
      await tester.pump(const Duration(milliseconds: 40));
      expect(_opacity(tester), allOf(greaterThan(0), lessThan(1)));
      await tester.pumpWidget(build(true));
      expect(_opacity(tester), 1);
      expect(created, 1, reason: 'not remounted');
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
    testWidgets('signing in fades the app in over the sign-in page, keeping it',
        (tester) async {
      var loginBuilds = 0;
      final login = Builder(builder: (_) {
        loginBuilds++;
        return const Text('login');
      });
      await tester.pumpWidget(MaterialApp(
        home: ShellFade(signedOutShell: true, child: login),
      ));
      final builds = loginBuilds;
      await tester.pumpWidget(const MaterialApp(
        home: ShellFade(signedOutShell: false, child: Text('app')),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('login'), findsOneWidget);
      expect(find.text('app'), findsOneWidget);
      expect(loginBuilds, builds, reason: 'not rebuilt or remounted');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(find.text('login'), findsNothing);
      expect(find.text('app'), findsOneWidget);
    });

    testWidgets('signing out drops the app at once, never rebuilding it',
        (tester) async {
      var loggedOut = false;
      final app = Builder(builder: (_) {
        if (loggedOut) throw StateError('built after sign-out');
        return const Text('app');
      });
      await tester.pumpWidget(MaterialApp(
        home: ShellFade(signedOutShell: false, child: app),
      ));
      loggedOut = true;
      await tester.pumpWidget(const MaterialApp(
        home: ShellFade(signedOutShell: true, child: Text('login')),
      ));
      expect(find.text('app'), findsNothing);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('login'), findsOneWidget);
    });

    testWidgets('signing out again mid-fade mounts a fresh sign-in page',
        (tester) async {
      var created = 0;
      Widget login() => _Probe(onCreate: () => created++);
      Widget build(bool out, Widget child) => MaterialApp(
            home: ShellFade(signedOutShell: out, child: child),
          );
      await tester.pumpWidget(build(true, login()));
      expect(created, 1);
      await tester.pumpWidget(build(false, const Text('app')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(build(true, login()));
      await tester.pump();
      expect(created, 2, reason: 'the fading page is not reused');
      expect(find.byType(_Probe), findsOneWidget);
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

class _Probe extends StatefulWidget {
  const _Probe({required this.onCreate});
  final VoidCallback onCreate;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  Widget build(BuildContext context) => const Text('login');
}

class _Mount extends StatefulWidget {
  const _Mount({required this.onCreate});
  final VoidCallback onCreate;

  @override
  State<_Mount> createState() => _MountState();
}

class _MountState extends State<_Mount> {
  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

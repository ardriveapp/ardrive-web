import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/permanence/ar_spend.dart';
import 'package:ardrive/permanence/permanence_panel.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  const gb = 1024 * 1024 * 1024;

  PermanenceSummary summary({
    Future<SpendLookup>? spend,
    Future<ArSpendTally>? arSpend,
    Future<NetworkCost?>? costToday,
  }) =>
      PermanenceSummary(
        totalBytes: 2 * gb,
        fileCount: 1200,
        driveCount: 3,
        bytesByYear: const {2022: gb, 2024: gb},
        costToday: costToday,
        spend: spend,
        arSpend: arSpend,
      );

  Future<void> pump(
    WidgetTester tester,
    PermanenceSummary summary, {
    double width = 460,
  }) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ArDriveTheme(
      themeData: lightTheme(),
      child: MaterialApp(
        home: Material(
          child: SingleChildScrollView(
            child: PermanencePanel(summary: summary),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('says what is stored, since when, and what it costs today',
      (tester) async {
    // 20 AR from the network, at $5 an AR.
    await pump(
      tester,
      summary(
        costToday: Future.value(NetworkCost(
          winston: BigInt.from(20) * BigInt.from(10).pow(12),
          usdPerAr: 5,
        )),
      ),
    );

    expect(find.textContaining('2.0 GiB'), findsOneWidget);
    expect(find.textContaining('1,200 files'), findsOneWidget);
    expect(find.textContaining('since 2022'), findsOneWidget);
    expect(find.text(r'$100'), findsOneWidget);
    expect(find.text('20.00 AR'), findsOneWidget,
        reason: 'the AR it comes from');
    expect(find.text('Network price to store it'), findsOneWidget);
    expect(find.textContaining('Turbo'), findsNothing,
        reason: 'the price of storage, not of a service');
  });

  group('the cost today', () {
    testWidgets('without a dollar rate is the AR price alone', (tester) async {
      await pump(
        tester,
        summary(
          costToday: Future.value(NetworkCost(
            winston: BigInt.from(15) * BigInt.from(10).pow(11),
            usdPerAr: null,
          )),
        ),
      );

      expect(find.text('1.50 AR'), findsOneWidget);
    });

    testWidgets('says so when the network cannot be reached', (tester) async {
      await pump(tester, summary(costToday: Future.value(null)));

      expect(find.text("couldn't reach the network"), findsOneWidget);
    });
  });

  test('a network price that cannot be read is no cost, not a wrong one',
      () async {
    expect(
      await loadNetworkCost(
        price: () async => throw Exception('gateway down'),
        usdPerAr: Future.value(4.0),
      ),
      isNull,
    );

    final cost = await loadNetworkCost(
      price: () async => BigInt.from(2) * BigInt.from(10).pow(12),
      usdPerAr: Future.value(4.0),
    );
    expect(cost!.ar, 2);
    expect(cost.usd, 8);
  });

  testWidgets('promises no duration, and no price per year', (tester) async {
    // "Stored for 200 years" read as a guarantee, and "$6.00 a year over 200
    // years" was a sum nobody could follow. Neither is said.
    await pump(tester, summary());

    expect(find.textContaining('Stored for', findRichText: true), findsNothing);
    expect(find.textContaining('a year', findRichText: true), findsNothing);
  });

  group('the spend', () {
    // Made inside each test, so it completes on the test's own clock.
    Future<SpendLookup> credits(double amount) => Future.value(
          SpendLookup.found(BigInt.from(amount * 1e12)),
        );

    testWidgets('is the credits used, with no dollars beside it',
        (tester) async {
      await pump(tester, summary(spend: credits(92.0812)));

      expect(find.text('SPENT'), findsOneWidget);
      expect(find.text('92.08'), findsOneWidget);
      expect(find.text('Turbo credits used'), findsOneWidget);
      expect(find.textContaining('estimated'), findsNothing,
          reason: 'credits used are exact');
    });

    testWidgets('says it could not be read, apart from finding none',
        (tester) async {
      await pump(
        tester,
        summary(spend: Future.value(const SpendLookup.failed())),
      );
      expect(find.text("couldn't read your credits"), findsOneWidget);

      await pump(
          tester, summary(spend: Future.value(const SpendLookup.none())));
      expect(find.text('no top-ups found'), findsOneWidget);
    });

    testWidgets('of a history too long to read in full shows no figure',
        (tester) async {
      await pump(
        tester,
        summary(spend: Future.value(const SpendLookup.tooMany())),
      );

      expect(find.text('more top-ups than we can count here'), findsOneWidget);
    });

    testWidgets('of credits not yet used says so', (tester) async {
      await pump(tester, summary(spend: credits(0)));

      expect(find.text('no credits used yet'), findsOneWidget);
    });
  });

  group('AR paid directly', () {
    ArSpendTally ar(double amount, int uploads, {bool complete = true}) =>
        ArSpendTally(
          winston: BigInt.from(amount * 1e12),
          uploads: uploads,
          lastHeight: 100,
          runMinHeight: complete ? null : 0,
          cursor: complete ? null : 'next',
        );

    // Made inside each test, so it completes on the test's own clock.
    Future<SpendLookup> used() =>
        Future.value(SpendLookup.found(BigInt.from(40e12)));

    testWidgets('sits under the credits, never added to them', (tester) async {
      await pump(
        tester,
        summary(spend: used(), arSpend: Future.value(ar(1.2345, 7))),
      );

      expect(find.text('40.00'), findsOneWidget);
      expect(find.text('+ 1.23 AR paid directly'), findsOneWidget);
    });

    testWidgets('is the figure when no credits were used', (tester) async {
      await pump(
        tester,
        summary(
          spend: Future.value(const SpendLookup.none()),
          arSpend: Future.value(ar(0.5, 3)),
        ),
      );

      expect(find.text('0.5 AR'), findsOneWidget);
      expect(find.text('paid directly in AR'), findsOneWidget);
    });

    testWidgets('an unfinished count says it is a lower bound', (tester) async {
      await pump(
        tester,
        summary(
          spend: used(),
          arSpend: Future.value(ar(2, 1000, complete: false)),
        ),
      );

      expect(find.text('+ at least 2.00 AR paid directly'), findsOneWidget);
    });

    testWidgets('says nothing when there is none', (tester) async {
      await pump(
        tester,
        summary(spend: used(), arSpend: Future.value(ArSpendTally.empty)),
      );

      expect(find.textContaining('AR'), findsNothing);
    });
  });

  testWidgets('keeps its fine print one tap away', (tester) async {
    await pump(tester, summary());

    expect(
        find.textContaining("isn't a bill", findRichText: true), findsNothing);

    await tester.tap(find.text('How these numbers work'));
    await tester.pumpAndSettle();

    expect(find.textContaining("isn't a bill", findRichText: true),
        findsOneWidget);
    expect(find.textContaining('Terms of Service', findRichText: true),
        findsOneWidget);
  });

  testWidgets('says plainly what each figure counts', (tester) async {
    await pump(tester, summary());
    await tester.tap(find.text('How these numbers work'));
    await tester.pumpAndSettle();

    final fineText = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((text) => text.text.toPlainText())
        .where((text) => text.contains(' is ') || text.contains(' counts '))
        .join('\n');

    expect(fineText, contains('Size counts every version'));
    expect(fineText, contains('Hidden drives'));
    expect(fineText, contains('network fees and ArDrive tips'));
    expect(fineText, contains('Neither is in dollars'));
    expect(fineText, contains("isn't what ArDrive or Turbo would charge"));
    expect(fineText, contains('Arweave says'),
        reason: "a duration is Arweave's claim, not ours");
    expect(fineText, isNot(contains(' - ')), reason: 'no dashes');
  });

  testWidgets('keeps its two figures side by side on a phone', (tester) async {
    // Stacked, the panel did not fit a phone, and nothing said it scrolled.
    await pump(tester, summary(), width: 340);

    final spend = tester.getTopLeft(find.text('SPENT'));
    final cost = tester.getTopLeft(find.text('COST TODAY'));

    expect(cost.dy, spend.dy, reason: 'one beside the other');
    expect(tester.takeException(), isNull);
  });

  testWidgets('stacks them only on a screen too narrow for that',
      (tester) async {
    await pump(tester, summary(), width: 260);

    final spend = tester.getTopLeft(find.text('SPENT'));
    final cost = tester.getTopLeft(find.text('COST TODAY'));

    expect(cost.dy, greaterThan(spend.dy));
  });

  // The profile card closes as it opens the panel, so the context that
  // opened it is gone by the time Share is pressed.
  testWidgets('opens the share card after what opened the panel has gone',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => ActivityTracker(),
      child: ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          home: Material(
            child: _Opener(
              onOpen: (context) => showPermanencePanel(context, summary()),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsNothing);

    await tester.tap(find.text('Share my permanence'));
    await tester.pumpAndSettle();

    // The card is drawn at a fixed size and the test font is wider than the
    // app's, so its text can overflow here. What this checks is that it
    // opened, from a context that was still there.
    expect('${tester.takeException()}', isNot(contains('deactivated')));
    expect(find.text('Share your permanence'), findsOneWidget);
  });

  test('sizes are in the units the rest of the app uses', () {
    // The drives list says GiB for 1024-based sizes; this said GB for the
    // same arithmetic, so the two looked like different numbers.
    expect(formatPermanenceSize(512), '0.5 KiB');
    expect(formatPermanenceSize(3 * 1024 * 1024), '3.0 MiB');
    expect(formatPermanenceSize((24.9 * gb).round()), '24.9 GiB');
    expect(formatPermanenceSize(150 * gb), '150 GiB');
    expect(formatPermanenceSize(2 * 1024 * gb), '2.0 TiB');
  });

  test('counts are separated by thousands, with a bullet between them', () {
    expect(
      [permanenceCount(21, 'drive'), permanenceCount(1776, 'file')]
          .join(permanenceSeparator),
      '21 drives  •  1,776 files',
    );
    expect(permanenceCount(1, 'file'), '1 file');
  });

  testWidgets('keeps a label for every year of a long history', (tester) async {
    // Six years filled the chart; a seventh and eighth pushed the oldest off
    // its top.
    await pump(
      tester,
      PermanenceSummary(
        totalBytes: 10 * gb,
        fileCount: 10,
        driveCount: 1,
        bytesByYear: {for (var y = 2017; y <= 2026; y++) y: gb},
      ),
    );

    expect(
      find.byWidgetPredicate(
        (w) => w is SizedBox && w.child is CustomPaint && w.height == 200,
      ),
      findsOneWidget,
      reason: 'twenty points a year',
    );
    expect(
      find.bySemanticsLabel(RegExp('2017, 1.0 GiB.*2026, 1.0 GiB')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  test('spreads the labels of two thin years apart', () {
    // 2025 and 2026 were small and sat together at the top of the chart, so
    // their labels touched.
    final ys = spreadStrataLabels(
      [110, 80, 40, 12, 6, 2],
      gap: 16,
      height: 120,
    );

    for (var i = 1; i < ys.length; i++) {
      expect(ys[i - 1] - ys[i], greaterThanOrEqualTo(16));
    }
    expect(ys.last, greaterThanOrEqualTo(8), reason: 'inside the top edge');
    expect(ys.first, lessThanOrEqualTo(112), reason: 'inside the bottom');
    expect(ys.take(3), [110, 80, 56],
        reason: 'the rest move no more than needed');
  });

  testWidgets('copies the text without closing the share card', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => ActivityTracker(),
      child: ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          home: Material(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPermanenceShare(context, summary()),
                child: const Text('Share'),
              ),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    // The card's fixed size overflows in the test font only; see above.
    tester.takeException();

    await tester.tap(find.text('Copy text'));
    await tester.pump();

    expect(copied, permanenceShareText(summary()));
    expect(find.text('Copied'), findsOneWidget, reason: 'says it is done');
    expect(find.text('Share your permanence'), findsOneWidget,
        reason: 'still open, for the image too');

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Copy text'), findsOneWidget);
    tester.takeException();
  });

  test('the share text carries no dollar figure and no promised duration', () {
    final text = permanenceShareText(summary());

    expect(text, contains('2.0 GiB'));
    expect(text, isNot(contains(r'$')));
    expect(text, isNot(contains('200')));
  });
}

/// A button that takes itself away as it is pressed, as the profile card
/// closes when it opens the panel.
class _Opener extends StatefulWidget {
  const _Opener({required this.onOpen});

  final void Function(BuildContext context) onOpen;

  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  bool _shown = true;

  @override
  Widget build(BuildContext context) => _shown
      ? Builder(
          builder: (context) => TextButton(
            onPressed: () {
              setState(() => _shown = false);
              widget.onOpen(context);
            },
            child: const Text('Open'),
          ),
        )
      : const SizedBox();
}

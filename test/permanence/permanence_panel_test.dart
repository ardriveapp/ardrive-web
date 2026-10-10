import 'package:ardrive/permanence/ar_spend.dart';
import 'package:ardrive/permanence/permanence_panel.dart';
import 'package:ardrive/permanence/spend_estimate.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const gb = 1024 * 1024 * 1024;

  PermanenceSummary summary({
    Future<SpendLookup>? spend,
    Future<ArSpendTally>? arSpend,
    double? usdPerGb,
  }) =>
      PermanenceSummary(
        totalBytes: 2 * gb,
        fileCount: 1200,
        driveCount: 3,
        bytesByYear: const {2022: gb, 2024: gb},
        usdPerGb: usdPerGb ?? 50,
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
    await pump(tester, summary());

    expect(find.textContaining('2.0 GB'), findsOneWidget);
    expect(find.textContaining('1,200 files'), findsOneWidget);
    expect(find.textContaining('since 2022'), findsOneWidget);
    // 2 GB at $50 a GB.
    expect(find.text(r'$100'), findsOneWidget);
  });

  testWidgets('promises no duration, and no price per year', (tester) async {
    // "Stored for 200 years" read as a guarantee, and "$6.00 a year over 200
    // years" was a sum nobody could follow. Neither is said.
    await pump(tester, summary());

    expect(find.textContaining('Stored for', findRichText: true), findsNothing);
    expect(find.textContaining('a year', findRichText: true), findsNothing);
  });

  group('the spend', () {
    testWidgets('is labelled an estimate', (tester) async {
      await pump(tester, summary());

      expect(find.text('ESTIMATED SPEND'), findsOneWidget);
      expect(find.text('SPENT'), findsNothing);
    });

    testWidgets('says it could not be read, apart from finding none',
        (tester) async {
      await pump(
        tester,
        summary(spend: Future.value(const SpendLookup.failed())),
      );
      expect(find.text("couldn't read your top-ups"), findsOneWidget);

      await pump(
          tester, summary(spend: Future.value(const SpendLookup.none())));
      expect(find.text('no top-ups found'), findsOneWidget);
    });

    testWidgets('of credits only granted is nothing', (tester) async {
      await pump(
        tester,
        summary(
          spend: Future.value(const SpendLookup.found(
            SpendEstimate(usd: 0, paidCount: 0, grantCount: 3),
          )),
        ),
      );

      expect(find.text(r'$0'), findsOneWidget);
      expect(find.text('3 credit grants, nothing bought'), findsOneWidget);
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
    Future<SpendLookup> bought() => Future.value(const SpendLookup.found(
          SpendEstimate(usd: 40, paidCount: 2, grantCount: 0),
        ));

    testWidgets('sits under the dollars, never added to them', (tester) async {
      await pump(
        tester,
        summary(spend: bought(), arSpend: Future.value(ar(1.2345, 7))),
      );

      expect(find.text(r'$40'), findsOneWidget);
      expect(find.text('+ 1.2345 AR paid directly'), findsOneWidget);
    });

    testWidgets('is the figure when nothing was bought', (tester) async {
      await pump(
        tester,
        summary(
          spend: Future.value(const SpendLookup.none()),
          arSpend: Future.value(ar(0.5, 3)),
        ),
      );

      expect(find.text('0.5 AR'), findsOneWidget);
      expect(find.text('paid directly, 3 uploads'), findsOneWidget);
    });

    testWidgets('an unfinished count says it is a lower bound', (tester) async {
      await pump(
        tester,
        summary(
          spend: bought(),
          arSpend: Future.value(ar(2, 1000, complete: false)),
        ),
      );

      expect(find.text('+ at least 2 AR paid directly'), findsOneWidget);
    });

    testWidgets('says nothing when there is none', (tester) async {
      await pump(
        tester,
        summary(spend: bought(), arSpend: Future.value(ArSpendTally.empty)),
      );

      expect(find.textContaining('AR'), findsNothing);
    });
  });

  testWidgets('keeps its fine print one tap away', (tester) async {
    await pump(tester, summary());

    expect(find.textContaining("isn't a receipt", findRichText: true),
        findsNothing);

    await tester.tap(find.text('How these numbers work'));
    await tester.pumpAndSettle();

    expect(find.textContaining("isn't a receipt", findRichText: true),
        findsOneWidget);
    expect(find.textContaining('Terms of Service', findRichText: true),
        findsOneWidget);
  });

  testWidgets('stacks its two figures on a phone', (tester) async {
    await pump(tester, summary(), width: 340);

    final spend = tester.getTopLeft(find.text('ESTIMATED SPEND'));
    final cost = tester.getTopLeft(find.text('COST TODAY'));

    expect(cost.dy, greaterThan(spend.dy), reason: 'one above the other');
    expect(tester.takeException(), isNull);
  });

  test('the share text carries no dollar figure and no promised duration', () {
    final text = permanenceShareText(summary());

    expect(text, contains('2.0 GB'));
    expect(text, isNot(contains(r'$')));
    expect(text, isNot(contains('200')));
  });
}

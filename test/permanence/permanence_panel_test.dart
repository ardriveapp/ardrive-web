import 'package:ardrive/permanence/permanence_panel.dart';
import 'package:ardrive/permanence/spend_estimate.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const gb = 1024 * 1024 * 1024;

  PermanenceSummary summary({Future<SpendLookup>? spend, double? usdPerGb}) =>
      PermanenceSummary(
        totalBytes: 2 * gb,
        fileCount: 1200,
        driveCount: 3,
        bytesByYear: const {2022: gb, 2024: gb},
        usdPerGb: usdPerGb ?? 50,
        spend: spend,
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

  testWidgets('promises no duration of its own', (tester) async {
    // "Stored for 200 years" read as a guarantee. The panel says what the
    // storage is designed for, and leaves the 200 years to Arweave.
    await pump(tester, summary());

    expect(find.textContaining('Stored for'), findsNothing);
    expect(find.textContaining('Designed to be permanent', findRichText: true),
        findsOneWidget);
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

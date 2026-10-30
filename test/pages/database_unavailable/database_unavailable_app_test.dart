import 'package:ardrive/pages/database_unavailable/database_unavailable_app.dart';
import 'package:ardrive_logger/ardrive_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  var tried = 0;
  var helped = 0;
  final shared = <LogExportInfo>[];

  Future<void> pump(WidgetTester tester) async {
    tried = 0;
    helped = 0;
    shared.clear();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(DatabaseUnavailableApp(
      onTryAgain: () => tried++,
      onHelpCenter: () => helped++,
      onShareLogs: (info) async => shared.add(info),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('says what failed and that files on Arweave are safe',
      (tester) async {
    await pump(tester);

    expect(find.text('ArDrive could not start'), findsOneWidget);
    expect(
        find.textContaining('Your files on Arweave are safe'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Help center'), findsOneWidget);
    expect(find.text('Share logs'), findsOneWidget);
  });

  testWidgets('offers nothing that deletes data', (tester) async {
    await pump(tester);

    expect(
        find.textContaining(RegExp('reset|delete|clear', caseSensitive: false)),
        findsNothing);
  });

  testWidgets('each button does its one thing', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Try again'));
    expect((tried, helped, shared.length), (1, 0, 0));

    await tester.tap(find.text('Help center'));
    expect((tried, helped, shared.length), (1, 1, 0));

    await tester.tap(find.text('Share logs'));
    await tester.pump();
    expect((tried, helped, shared.length), (1, 1, 1));
    expect(shared.single.emailSupport, 'support@ardrive.io');
  });
}

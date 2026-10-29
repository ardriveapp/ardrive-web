import 'dart:async';

import 'package:ardrive/pages/database_unavailable/database_unavailable_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resetFailed =
      'Some data is still in use. Close other ArDrive tabs, then try again.';

  Future<void> pump(
    WidgetTester tester, {
    VoidCallback? onTryAgain,
    Future<bool> Function()? onReset,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(DatabaseUnavailableApp(
      onTryAgain: onTryAgain ?? () {},
      onReset: onReset ?? () async => true,
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('says what failed, that files are safe, and what a reset costs',
      (tester) async {
    await pump(tester);

    expect(find.text('ArDrive could not start'), findsOneWidget);
    expect(find.textContaining('Your files on Arweave are safe'),
        findsOneWidget);
    expect(find.textContaining('keyfile or recovery phrase'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Reset local data'), findsOneWidget);
    expect(find.text(resetFailed), findsNothing);
  });

  testWidgets('Try again calls back', (tester) async {
    var tried = 0;
    await pump(tester, onTryAgain: () => tried++);

    await tester.tap(find.text('Try again'));
    expect(tried, 1);
  });

  testWidgets('Reset local data resets, and says so when it could not',
      (tester) async {
    var resets = 0;
    final answer = Completer<bool>();
    await pump(tester, onReset: () {
      resets++;
      return answer.future;
    });

    await tester.tap(find.text('Reset local data'));
    await tester.pump();
    expect(resets, 1);

    answer.complete(false);
    await tester.pumpAndSettle();
    expect(find.text(resetFailed), findsOneWidget);
  });

  testWidgets('a reset that throws reads as one that could not finish',
      (tester) async {
    await pump(tester, onReset: () async => throw StateError('held'));

    await tester.tap(find.text('Reset local data'));
    await tester.pumpAndSettle();
    expect(find.text(resetFailed), findsOneWidget);
  });
}

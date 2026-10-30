import 'dart:io';

import 'package:ardrive/utils/pre_cache_assets.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the sign-in pictures loaded ahead of time', () {
    final all = [
      ...firstLoginImages(),
      ...firstLoginSvgs(light: true),
      ...firstLoginSvgs(light: false),
      ...laterLoginImages(),
      ...laterLoginSvgs(light: true),
      ...laterLoginSvgs(light: false),
    ];

    test('all exist', () {
      for (final path in all) {
        expect(File(path).existsSync(), isTrue, reason: path);
      }
    });

    test('are only ones a screen still shows', () {
      // Each was precached on every start, parsed on the main thread, after
      // the bento that showed them was replaced.
      const retired = [
        'bento-box-2-dark-mode.svg',
        'bento-box-2-light-mode.svg',
        'no_subscription.svg',
        'decentralized.svg',
        'permanent_accesible_data.svg',
        'price_calculator.svg',
        'dots.png',
      ];
      for (final path in all) {
        expect(retired.any(path.endsWith), isFalse, reason: path);
      }
    });

    test('first and later never overlap: each picture loads once', () {
      final first = {...firstLoginImages(), ...firstLoginSvgs(light: true)};
      final later = {...laterLoginImages(), ...laterLoginSvgs(light: true)};
      expect(first.intersection(later), isEmpty);
    });

    test('later leaves the first slide to the first paint', () {
      expect(laterLoginSvgs(light: true), hasLength(4));
      expect(laterLoginSvgs(light: true).first, contains('cant_be_changed'));
      expect(laterLoginSvgs(light: false).first, isNot(contains('_light')));
    });
  });

  testWidgets('waits before loading anything, so the first paint goes first',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(ArDriveApp(
      builder: (_) => MaterialApp(
        home: Builder(builder: (c) {
          context = c;
          return const SizedBox();
        }),
      ),
    ));
    final cache = tester.binding.imageCache;
    cache.clear();
    int requested() => cache.pendingImageCount + cache.currentSize;

    preCacheLaterLoginAssets(context, delay: const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 900));
    expect(requested(), 0);

    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    expect(requested(), greaterThan(0));
  });
}

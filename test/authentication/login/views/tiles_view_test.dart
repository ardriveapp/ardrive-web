import 'dart:io';

import 'package:ardrive/authentication/login/views/tiles/tiles_view.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wavehaus, so layouts are checked against real letter widths rather than the
/// test font's squares.
Future<void> _loadWavehaus() async {
  Future<ByteData> read(String path) async =>
      ByteData.view(Uint8List.fromList(File(path).readAsBytesSync()).buffer);
  const dir = 'packages/ardrive_ui/assets/fonts';
  final wavehaus = FontLoader('packages/ardrive_ui/Wavehaus');
  for (final f in [
    'Wavehaus-42Light.otf',
    'Wavehaus-66Book.otf',
    'Wavehaus-95SemiBold.otf',
    'Wavehaus-128Bold.otf',
  ]) {
    wavehaus.addFont(read('$dir/$f'));
  }
  await wavehaus.load();
}

void main() {
  setUpAll(_loadWavehaus);

  Future<void> pumpBento(
    WidgetTester tester, {
    required Size size,
    bool scrolling = false,
    bool still = false,
    Future<double?> Function()? price,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final bento = TilesView(loadPricePerGb: price ?? () async => 23.69);
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: still),
            child: Scaffold(
              body: scrolling
                  ? SingleChildScrollView(child: bento)
                  : SizedBox.fromSize(size: size, child: bento),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  // Timers and the drift run forever; a widget swap stops them.
  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  void expectAllFiveTiles() {
    expect(find.byKey(const Key('bentoPeopleHeading')), findsOneWidget);
    expect(find.text('Put it online, for good'), findsOneWidget);
    expect(
        find.textContaining('Permanent', findRichText: true), findsOneWidget);
    expect(find.byKey(const Key('bentoSlideTitle')), findsOneWidget);
    expect(find.text('What it costs'), findsOneWidget);
  }

  testWidgets('three columns keep all five tiles and what a GB holds',
      (tester) async {
    await pumpBento(tester, size: const Size(696, 868));
    expectAllFiveTiles();
    expect(find.byKey(const Key('bentoEquivalents')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await done(tester);
  });

  testWidgets('two columns keep all five tiles', (tester) async {
    await pumpBento(tester, size: const Size(496, 816));
    expectAllFiveTiles();
    expect(find.byKey(const Key('bentoEquivalents')), findsNothing);
    expect(tester.takeException(), isNull);
    await done(tester);
  });

  testWidgets('a phone stacks all five tiles in the scroll view',
      (tester) async {
    await pumpBento(tester, size: const Size(390, 844), scrolling: true);
    expectAllFiveTiles();
    expect(tester.takeException(), isNull);
    await done(tester);
  });

  testWidgets('hovering a person names them in the heading', (tester) async {
    await pumpBento(tester, size: const Size(696, 868));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('Journalists')));
    await tester.pump();

    final heading =
        tester.widget<Text>(find.byKey(const Key('bentoPeopleHeading')));
    expect(heading.textSpan!.toPlainText(), 'ArDrive is for Journalists');
    expect(find.text('Publish work that stays up.'), findsOneWidget);
    await done(tester);
  });

  testWidgets('a dot picks its slide', (tester) async {
    await pumpBento(tester, size: const Size(696, 868));
    expect(find.text('Private files stay private'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bentoDot-Features-2')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Proof of when it was saved'), findsOneWidget);
    await done(tester);
  });

  testWidgets('reduce motion: the whole name, and nothing advances',
      (tester) async {
    await pumpBento(tester, size: const Size(696, 868), still: true);
    expect(
      tester.widget<Text>(find.byKey(const Key('bentoTypedName'))).data,
      'maya',
    );
    await tester.pump(const Duration(seconds: 12));
    expect(find.text('Private files stay private'), findsOneWidget);
    expect(find.text('Educators'), findsOneWidget);
    await done(tester);
  });

  testWidgets('the price shows when Turbo answers', (tester) async {
    await pumpBento(tester, size: const Size(696, 868));
    expect(
        find.textContaining('\$23.69', findRichText: true), findsOneWidget);
    await done(tester);
  });

  testWidgets('the price line is left out when Turbo can\'t be reached',
      (tester) async {
    await pumpBento(
      tester,
      size: const Size(696, 868),
      price: () async => null,
    );
    expect(find.byKey(const Key('bentoPrice')), findsNothing);
    expect(find.byKey(const Key('bentoPriceLoading')), findsNothing);
    expect(find.text('Free to try. Paid once, no subscription.'), findsOneWidget);
    await done(tester);
  });
}

import 'dart:async';
import 'dart:io';

import 'package:ardrive/authentication/login/views/tiles/tiles_view.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  void expectTheBill() {
    expect(find.text('1 GB, saved for good'), findsOneWidget);
    expect(find.text('Subscription'), findsOneWidget);
    expect(find.text('\$0'), findsOneWidget);
    expect(find.text('To try it'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
    expect(find.text('See prices'), findsOneWidget);
  }

  const holds = Key('bentoCostHolds');

  testWidgets('three columns keep all five tiles and what a GB holds',
      (tester) async {
    await pumpBento(tester, size: const Size(696, 868));
    expectAllFiveTiles();
    expectTheBill();
    expect(find.byKey(holds), findsOneWidget);
    expect(tester.takeException(), isNull);
    await done(tester);
  });

  testWidgets('two columns keep all five tiles and the whole bill',
      (tester) async {
    await pumpBento(tester, size: const Size(496, 816));
    expectAllFiveTiles();
    expectTheBill();
    expect(find.byKey(holds), findsNothing);
    expect(tester.takeException(), isNull);
    await done(tester);
  });

  testWidgets('a phone stacks all five tiles in the scroll view',
      (tester) async {
    await pumpBento(tester, size: const Size(390, 844), scrolling: true);
    expectAllFiveTiles();
    expectTheBill();
    expect(find.byKey(holds), findsOneWidget);
    expect(tester.takeException(), isNull);
    await done(tester);
  });

  // The bento beside the panel at each login width: 1440, 1280 and 1024 wide
  // windows 832 and 900 tall, and the narrowest side-by-side window, 834.
  for (final size in const [
    Size(708, 884),
    Size(708, 816),
    Size(628, 884),
    Size(628, 816),
    Size(500, 884),
    Size(500, 816),
    Size(405, 816),
  ]) {
    testWidgets(
        'the bill fits at ${size.width.toInt()} x ${size.height.toInt()}',
        (tester) async {
      await pumpBento(tester, size: size);
      expectTheBill();
      expect(tester.takeException(), isNull);
      await done(tester);
    });
  }

  testWidgets('each value sits on its label\'s baseline, flush right',
      (tester) async {
    await pumpBento(tester, size: const Size(696, 868));
    // The first line's baseline, from the top of the page.
    double baseline(Finder finder) {
      final text = tester.widget<Text>(finder);
      final painter = TextPainter(
        text: TextSpan(
          text: text.data,
          style: DefaultTextStyle.of(tester.element(finder))
              .style
              .merge(text.style),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      addTearDown(painter.dispose);
      return tester.getTopLeft(finder).dy +
          painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    }

    for (final (label, value) in [
      ('1 GB, saved for good', '\$23.69'),
      ('Subscription', '\$0'),
      ('To try it', 'Free'),
    ]) {
      expect(baseline(find.text(value)),
          moreOrLessEquals(baseline(find.text(label)), epsilon: 0.5),
          reason: label);
    }
    final right = tester.getTopRight(find.text('Free')).dx;
    expect(tester.getTopRight(find.text('\$0')).dx, right);
    expect(tester.getTopRight(find.text('\$23.69')).dx, right);
    await done(tester);
  });

  // The two-column tile, beside the panel in an 834 and a 1024 wide window.
  for (final size in const [
    Size(405, 816),
    Size(405, 884),
    Size(500, 816),
    Size(500, 884),
  ]) {
    testWidgets(
        'the narrow tile keeps the price label on one line at '
        '${size.width.toInt()} x ${size.height.toInt()}', (tester) async {
      await pumpBento(tester, size: size);
      final label = find.text('1 GB, saved for good');
      final style = DefaultTextStyle.of(tester.element(label))
          .style
          .merge(tester.widget<Text>(label).style);
      expect(tester.getSize(label).height,
          lessThan(style.fontSize! * style.height! * 1.5),
          reason: 'one line');
      // The price is on the line below, flush right with the other values.
      expect(tester.getTopLeft(find.text('\$23.69')).dy,
          greaterThan(tester.getBottomLeft(label).dy - 1));
      expect(tester.getTopRight(find.text('\$23.69')).dx,
          tester.getTopRight(find.text('Free')).dx);
      expect(tester.takeException(), isNull);
      await done(tester);
    });
  }

  testWidgets('a screen reader hears the tile once, as one link',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpBento(tester, size: const Size(696, 868));
    final labels = <String>[];
    void collect(SemanticsNode node) {
      labels.add(node.label);
      node.visitChildren((child) {
        collect(child);
        return true;
      });
    }

    var root = tester.getSemantics(find.text('What it costs'));
    while (root.parent != null) {
      root = root.parent!;
    }
    collect(root);
    int count(String text) =>
        labels.map((l) => text.allMatches(l).length).fold(0, (a, b) => a + b);
    expect(count('What it costs'), 1);
    expect(count('See prices'), 1);
    final link = tester.getSemantics(find.text('What it costs'));
    expect(link.hasFlag(SemanticsFlag.isLink), isTrue);
    expect(link.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(link.label, contains('See prices'));
    await done(tester);
    semantics.dispose();
  });

  testWidgets('Free is in the success colour', (tester) async {
    await pumpBento(tester, size: const Size(696, 868));
    final colors = ArDriveTheme.of(tester.element(find.text('Free')))
        .themeData
        .colorTokens;
    expect(tester.widget<Text>(find.text('Free')).style!.color,
        colors.statusSuccessFg);
    await done(tester);
  });

  testWidgets('only a tile that is a link lifts under the pointer',
      (tester) async {
    await pumpBento(tester, size: const Size(696, 868));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    Future<double> lift(Finder inTile) async {
      final before = tester.getTopLeft(inTile).dy;
      await mouse.moveTo(tester.getCenter(inTile));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final after = tester.getTopLeft(inTile).dy;
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      return before - after;
    }

    expect(await lift(find.text('What it costs')), 2);
    expect(await lift(find.text('Put it online, for good')), 0);
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

  // The sign-in page holds the bento still while the database opens: every
  // frame it drew there was main-thread time the database's worker waited
  // for.
  testWidgets('held still by the page, it draws nothing until let go',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(696, 868);
    addTearDown(tester.view.reset);
    var moving = false;
    late StateSetter setMoving;
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: StatefulBuilder(builder: (context, setState) {
            setMoving = setState;
            return TickerMode(
              enabled: moving,
              child: Scaffold(
                body: SizedBox.fromSize(
                  size: const Size(696, 868),
                  child: TilesView(loadPricePerGb: () async => 23.69),
                ),
              ),
            );
          }),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      tester.widget<Text>(find.byKey(const Key('bentoTypedName'))).data,
      'maya',
      reason: 'the whole name, not typed out',
    );
    await tester.pump(const Duration(seconds: 12));
    expect(find.text('Private files stay private'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'nothing asks for another frame');

    setMoving(() => moving = true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Private files stay private'), findsNothing,
        reason: 'let go, the slides move on');
    await done(tester);
  });

  testWidgets('the price shows when Turbo answers', (tester) async {
    await pumpBento(tester, size: const Size(696, 868));
    expect(find.text('\$23.69'), findsOneWidget);
    expect(find.textContaining('USD'), findsNothing);
    await done(tester);
  });

  testWidgets('the bill keeps its place while the price loads', (tester) async {
    final price = Completer<double?>();
    await pumpBento(
      tester,
      size: const Size(696, 868),
      price: () => price.future,
    );
    expect(find.byKey(const Key('bentoPriceLoading')), findsOneWidget);
    expect(find.text('1 GB, saved for good'), findsOneWidget);
    final subscription = tester.getTopLeft(find.text('Subscription'));

    price.complete(23.69);
    await tester.pump();
    expect(find.byKey(const Key('bentoPriceLoading')), findsNothing);
    expect(find.text('\$23.69'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Subscription')), subscription);
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
    expect(find.text('1 GB, saved for good'), findsNothing);
    expect(find.text('Subscription'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await done(tester);
  });
}

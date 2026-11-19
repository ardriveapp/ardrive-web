import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    group('ArDriveGalleryScrubber ($mode)', () {
      late ArDriveSectionedGalleryController controller;
      setUp(() => controller = ArDriveSectionedGalleryController());
      tearDown(() => controller.dispose());

      Future<void> pump(
        WidgetTester tester, {
        Size screen = const Size(1000, 600),
        bool reduceMotion = false,
      }) async {
        tester.view.physicalSize = screen;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(ArDriveApp(
          themeData: ArDriveThemeData(
            colorTokens: dark
                ? ArDriveColorTokens.darkMode()
                : ArDriveColorTokens.lightMode(),
          ),
          builder: (context) => MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: screen,
                disableAnimations: reduceMotion,
              ),
              child: Scaffold(
                body: Stack(children: [
                  Positioned.fill(
                    child: ArDriveSectionedGallery(
                      controller: controller,
                      targetRowHeight: 100,
                      sections: [
                        for (var i = 0; i < 3; i++)
                          ArDriveGallerySection(
                            key: 's$i',
                            itemCount: 60,
                            header: Text('Month $i'),
                          ),
                      ],
                      aspectRatioOf: (_) => 1,
                      tileBuilder: (c, i, s) => const SizedBox(),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    child: ArDriveGalleryScrubber(
                      controller: controller,
                      semanticLabel: 'Timeline',
                      entries: [
                        for (var i = 0; i < 3; i++)
                          ArDriveGalleryScrubberEntry(
                            section: i,
                            title: 'Month $i',
                            tick: '${2020 + i}',
                          ),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ));
        await tester.pump();
        await tester.pump();
      }

      ArDriveColorTokens tokens(WidgetTester tester) =>
          ArDriveTheme.of(tester.element(find.byType(Scaffold)))
              .themeData
              .colorTokens;

      Color yearColor(WidgetTester tester, String year) => tester
          .widget<Text>(find.byKey(ValueKey('gallery-scrubber-year-$year')))
          .style!
          .color!;

      double fadeOpacity(WidgetTester tester) => tester
          .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('gallery-scrubber-fade')))
          .opacity;

      testWidgets('a faint track the labels sit along', (tester) async {
        await pump(tester);
        final track = tester.widget<Container>(
            find.byKey(const ValueKey('gallery-scrubber-track')));
        expect(track.color, tokens(tester).strokeLow);
        // Easy to grab: at least 24 px wide.
        expect(tester.getSize(find.byType(ArDriveGalleryScrubber)).width,
            greaterThanOrEqualTo(24));
      });

      testWidgets('the marker follows the scroll position', (tester) async {
        await pump(tester);
        final thumb = find.byKey(const ValueKey('gallery-scrubber-thumb'));
        final at0 = tester.getTopLeft(thumb).dy;
        controller.jumpToSection(2);
        await tester.pump();
        await tester.pump();
        expect(tester.getTopLeft(thumb).dy, greaterThan(at0 + 50));
        // Always on the track on a wide screen.
        expect(tester.widget<AnimatedOpacity>(thumb).opacity, 1);
      });

      testWidgets('the current year is in textHigh, the others in textLow',
          (tester) async {
        await pump(tester);
        final t = tokens(tester);
        expect(yearColor(tester, '2020'), t.textHigh);
        expect(yearColor(tester, '2021'), t.textLow);
        controller.jumpToSection(2);
        await tester.pump();
        await tester.pump();
        expect(yearColor(tester, '2020'), t.textLow);
        expect(yearColor(tester, '2022'), t.textHigh);
      });

      testWidgets('at rest it sits back, and comes forward on hover',
          (tester) async {
        await pump(tester);
        expect(fadeOpacity(tester), closeTo(0.4, 0.001));

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse
            .moveTo(tester.getCenter(find.byType(ArDriveGalleryScrubber)));
        await tester.pump();
        expect(fadeOpacity(tester), 1);

        await mouse.moveTo(const Offset(5, 5));
        await tester.pump();
        expect(fadeOpacity(tester), closeTo(0.4, 0.001));
      });

      testWidgets('it comes forward while scrolling, then sits back',
          (tester) async {
        await pump(tester);
        controller.scroll.jumpTo(300);
        await tester.pump();
        expect(fadeOpacity(tester), 1);
        await tester.pump(const Duration(seconds: 2));
        expect(fadeOpacity(tester), closeTo(0.4, 0.001));
      });

      testWidgets('with reduced motion it just stays forward', (tester) async {
        await pump(tester, reduceMotion: true);
        expect(fadeOpacity(tester), 1);
        final fade = tester.widget<AnimatedOpacity>(
            find.byKey(const ValueKey('gallery-scrubber-fade')));
        expect(fade.duration, Duration.zero);
      });

      testWidgets('a phone has no track and no labels, only a handle',
          (tester) async {
        await pump(tester, screen: const Size(390, 800));
        expect(
            find.byKey(const ValueKey('gallery-scrubber-track')), findsNothing);
        expect(find.byKey(const ValueKey('gallery-scrubber-year-2020')),
            findsNothing);
        final thumb = find.byKey(const ValueKey('gallery-scrubber-thumb'));
        expect(tester.widget<AnimatedOpacity>(thumb).opacity, 0);
        controller.scroll.jumpTo(300);
        await tester.pump();
        expect(tester.widget<AnimatedOpacity>(thumb).opacity, 1);
      });
    });
  }
}

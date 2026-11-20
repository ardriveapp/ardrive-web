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
        expect(track.color, tokens(tester).strokeMid);
        // Easy to grab: at least 24 px wide.
        expect(tester.getSize(find.byType(ArDriveGalleryScrubber)).width,
            greaterThanOrEqualTo(24));
      });

      testWidgets('the track widens a little while it is in use',
          (tester) async {
        await pump(tester);
        double trackWidth() => tester
            .getSize(find.byKey(const ValueKey('gallery-scrubber-track')))
            .width;
        expect(trackWidth(), 2);
        controller.scroll.jumpTo(300);
        await tester.pump();
        expect(trackWidth(), 3);
      });

      testWidgets('the marker is a clear pill: 4 x 24, iconHigh',
          (tester) async {
        await pump(tester);
        final thumb = find.byKey(const ValueKey('gallery-scrubber-thumb'));
        final box = tester.widget<Container>(
            find.descendant(of: thumb, matching: find.byType(Container)));
        final deco = box.decoration! as BoxDecoration;
        expect(deco.color, tokens(tester).iconHigh);
        expect(deco.borderRadius, isNotNull);
        expect(
            tester.getSize(
                find.descendant(of: thumb, matching: find.byType(Container))),
            const Size(4, 24));
      });

      testWidgets('hovering over the year labels brings it forward',
          (tester) async {
        await pump(tester);
        final label = find.byKey(const ValueKey('gallery-scrubber-year-2021'));
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        // The label's far left edge: it must be inside the hover area.
        await mouse.moveTo(tester.getTopLeft(label) + const Offset(1, 3));
        await tester.pump();
        expect(fadeOpacity(tester), 1);
      });

      testWidgets('non-current years read at 3:1 against the page at rest',
          (tester) async {
        await pump(tester);
        final page = ArDriveTheme.of(tester.element(find.byType(Scaffold)))
            .themeData
            .backgroundColor;
        final label = yearColor(tester, '2021');
        // The label is drawn at rest opacity over the page.
        final shown = Color.alphaBlend(
            label.withOpacity(ArDriveGalleryScrubber.restOpacity), page);
        double lum(Color c) => c.computeLuminance();
        final hi = lum(shown) > lum(page) ? shown : page;
        final lo = lum(shown) > lum(page) ? page : shown;
        expect((lum(hi) + 0.05) / (lum(lo) + 0.05), greaterThanOrEqualTo(3));
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

      testWidgets('the current year is in textHigh, the others in textMid',
          (tester) async {
        await pump(tester);
        final t = tokens(tester);
        expect(yearColor(tester, '2020'), t.textHigh);
        expect(yearColor(tester, '2021'), t.textMid);
        controller.jumpToSection(2);
        await tester.pump();
        await tester.pump();
        expect(yearColor(tester, '2020'), t.textMid);
        expect(yearColor(tester, '2022'), t.textHigh);
      });

      testWidgets('at rest it sits back, and comes forward on hover',
          (tester) async {
        await pump(tester);
        expect(fadeOpacity(tester),
            closeTo(ArDriveGalleryScrubber.restOpacity, 0.001));

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse
            .moveTo(tester.getCenter(find.byType(ArDriveGalleryScrubber)));
        await tester.pump();
        expect(fadeOpacity(tester), 1);

        await mouse.moveTo(const Offset(5, 5));
        await tester.pump();
        expect(fadeOpacity(tester),
            closeTo(ArDriveGalleryScrubber.restOpacity, 0.001));
      });

      testWidgets('it comes forward while scrolling, then sits back',
          (tester) async {
        await pump(tester);
        controller.scroll.jumpTo(300);
        await tester.pump();
        expect(fadeOpacity(tester), 1);
        await tester.pump(const Duration(seconds: 2));
        expect(fadeOpacity(tester),
            closeTo(ArDriveGalleryScrubber.restOpacity, 0.001));
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

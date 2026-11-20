import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The phone sizes follow the screen, not the room a gallery is given: a
/// details panel beside it narrows it, and it must stay a desktop gallery.
void main() {
  Future<void> pump(WidgetTester tester, Widget gallery,
      {required Size screen, required double width}) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, height: 600, child: gallery),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  double firstTileHeight(WidgetTester tester) =>
      tester.getSize(find.byKey(const ValueKey('t0'))).height;

  Widget justified({bool? isPhone}) => ArDriveJustifiedGallery(
        isPhone: isPhone,
        itemCount: 20,
        aspectRatioOf: (_) => 1,
        tileBuilder: (c, i, s) => SizedBox(key: ValueKey('t$i')),
      );

  Widget sectioned({bool? isPhone}) => ArDriveSectionedGallery(
        isPhone: isPhone,
        controller: ArDriveSectionedGalleryController(),
        sections: const [ArDriveGallerySection(key: 'a', itemCount: 20)],
        aspectRatioOf: (_) => 1,
        tileBuilder: (c, i, s) => SizedBox(key: ValueKey('t$i')),
      );

  for (final entry
      in {'justified': justified, 'sectioned': sectioned}.entries) {
    group(entry.key, () {
      testWidgets('a narrow gallery on a desktop screen keeps desktop rows',
          (tester) async {
        await pump(tester, entry.value(),
            screen: const Size(1440, 900), width: 600);
        expect(
            firstTileHeight(tester), greaterThan(galleryPhoneRowHeight * 1.5));
      });

      testWidgets('a phone screen gets phone rows', (tester) async {
        await pump(tester, entry.value(),
            screen: const Size(390, 800), width: 390);
        expect(
            firstTileHeight(tester), lessThan(galleryDesktopRowHeight * 0.75));
      });

      testWidgets('isPhone overrides the screen', (tester) async {
        await pump(tester, entry.value(isPhone: true),
            screen: const Size(1440, 900), width: 600);
        expect(
            firstTileHeight(tester), lessThan(galleryDesktopRowHeight * 0.75));
      });
    });
  }
}

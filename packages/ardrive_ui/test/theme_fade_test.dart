import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('switching theme fades the old look out, then removes it',
      (tester) async {
    await tester.pumpWidget(ArDriveApp(
      key: arDriveAppKey,
      builder: (context) => Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: ArDriveTheme.of(context).themeData.backgroundColor,
        ),
      ),
    ));

    arDriveAppKey.currentState!.changeTheme(ArDriveThemes.light);
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(RawImage), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(RawImage), findsNothing);
  });

  testWidgets('a slow first frame does not use up the fade', (tester) async {
    await tester.pumpWidget(ArDriveApp(
      key: arDriveAppKey,
      builder: (context) => const SizedBox(),
    ));
    arDriveAppKey.currentState!.changeTheme(ArDriveThemes.light);
    await tester.pump();
    // The frame that rebuilt the app took a second.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(RawImage), findsOneWidget);
  });

  testWidgets('quick switches free every snapshot', (tester) async {
    final disposed = <Object>[];
    debugOnThemeSnapshotDisposed = disposed.add;
    addTearDown(() => debugOnThemeSnapshotDisposed = null);

    await tester.pumpWidget(ArDriveApp(
      key: arDriveAppKey,
      builder: (context) => const SizedBox(),
    ));
    final state = arDriveAppKey.currentState!;
    state.changeTheme(ArDriveThemes.light);
    await tester.pump();
    state.changeTheme(ArDriveThemes.dark);
    await tester.pump();
    state.changeTheme(ArDriveThemes.light);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(RawImage), findsNothing);
    // Three snapshots taken, all freed (the last when the fade ended).
    expect(disposed.length, 3);
  });

  testWidgets('reduced motion switches at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(ArDriveApp(
      key: arDriveAppKey,
      builder: (context) => const SizedBox(),
    ));
    arDriveAppKey.currentState!.changeTheme(ArDriveThemes.light);
    await tester.pump();
    expect(find.byType(RawImage), findsNothing);
  });
}

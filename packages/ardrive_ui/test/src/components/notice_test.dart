import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(body: Center(child: child)),
        ),
      );

  BoxDecoration decorationOf(WidgetTester tester) => tester
      .widget<Container>(find.descendant(
          of: find.byType(ArDriveNotice), matching: find.byType(Container)))
      .decoration! as BoxDecoration;

  testWidgets('shows its title, message and action', (tester) async {
    var retried = false;
    await tester.pumpWidget(wrap(ArDriveNotice(
      type: ArDriveNoticeType.error,
      title: 'Upload failed',
      message: 'The network went away.',
      actionLabel: 'Retry',
      onAction: () => retried = true,
    )));

    expect(find.text('Upload failed'), findsOneWidget);
    expect(find.text('The network went away.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);

    final button =
        tester.widget<ArDriveButtonNew>(find.byType(ArDriveButtonNew));
    expect(button.size, ArDriveButtonSize.compact,
        reason: 'a button inside a notice is the compact size');
  });

  testWidgets('each type takes its own status colours', (tester) async {
    final tokens = ArDriveColorTokens.darkMode();
    final expected = {
      ArDriveNoticeType.info: tokens.statusInfoContainer,
      ArDriveNoticeType.warning: tokens.statusWarningContainer,
      ArDriveNoticeType.error: tokens.statusErrorContainer,
      ArDriveNoticeType.success: tokens.statusSuccessContainer,
    };
    for (final MapEntry(key: type, value: container) in expected.entries) {
      await tester.pumpWidget(wrap(ArDriveNotice(type: type, message: 'x')));
      expect(decorationOf(tester).color, container, reason: '$type');
    }
  });

  testWidgets('each type has its own icon', (tester) async {
    final expected = {
      ArDriveNoticeType.info: ArDriveIconsData.info,
      ArDriveNoticeType.warning: ArDriveIconsData.triangle,
      ArDriveNoticeType.error: ArDriveIconsData.close_circle,
      ArDriveNoticeType.success: ArDriveIconsData.check_cirle,
    };
    for (final MapEntry(key: type, value: icon) in expected.entries) {
      await tester.pumpWidget(wrap(ArDriveNotice(type: type, message: 'x')));
      expect(
          tester
              .widget<ArDriveIcon>(find.descendant(
                  of: find.byType(ArDriveNotice),
                  matching: find.byType(ArDriveIcon)))
              .icon,
          icon,
          reason: '$type');
    }
  });

  testWidgets('shows a close button only when it can be dismissed',
      (tester) async {
    await tester.pumpWidget(
        wrap(const ArDriveNotice(type: ArDriveNoticeType.info, message: 'x')));
    expect(find.byTooltip('Dismiss'), findsNothing);

    var dismissed = false;
    await tester.pumpWidget(wrap(ArDriveNotice(
      type: ArDriveNoticeType.info,
      message: 'x',
      onDismiss: () => dismissed = true,
    )));
    await tester.tap(find.byTooltip('Dismiss'));
    expect(dismissed, isTrue);
  });

  testWidgets('a banner spans the width with square corners', (tester) async {
    await tester.pumpWidget(wrap(const ArDriveNotice(
      type: ArDriveNoticeType.warning,
      message: 'Maintenance tonight',
      layout: ArDriveNoticeLayout.banner,
    )));

    expect(decorationOf(tester).borderRadius, isNull);
    expect(tester.getSize(find.byType(ArDriveNotice)).width,
        tester.view.physicalSize.width / tester.view.devicePixelRatio);
  });

  testWidgets('an inline notice has rounded corners', (tester) async {
    await tester.pumpWidget(
        wrap(const ArDriveNotice(type: ArDriveNoticeType.info, message: 'x')));

    expect(decorationOf(tester).borderRadius,
        BorderRadius.circular(ArDriveRadius.md));
  });

  testWidgets('an action without a callback is shown disabled', (tester) async {
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => const MaterialApp(
          home: Scaffold(
            body: ArDriveNotice(
              type: ArDriveNoticeType.info,
              message: 'A newer version is available',
              actionLabel: 'Get latest',
            ),
          ),
        ),
      ),
    );

    final action = tester.widget<ArDriveButtonNew>(
      find.widgetWithText(ArDriveButtonNew, 'Get latest'),
    );
    expect(action.isDisabled, isTrue);
  });

  testWidgets('a leading widget stands where the icon is, at its size',
      (tester) async {
    await tester.pumpWidget(wrap(const ArDriveNotice(
      type: ArDriveNoticeType.info,
      message: 'Syncing 2 drives',
      leading: ArDriveSpinner(),
    )));
    await tester.pump();

    expect(find.byType(ArDriveSpinner), findsOneWidget);
    expect(find.byType(ArDriveIcon), findsNothing,
        reason: 'the leading widget replaces the icon');
    // The icon's 20 px slot, so the text does not move when it is swapped
    // back for the icon.
    final slot = find.ancestor(
      of: find.byType(ArDriveSpinner),
      matching: find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 20 && w.height == 20,
      ),
    );
    expect(slot, findsOneWidget);
  });

  testWidgets('without one it shows the type\'s icon', (tester) async {
    await tester.pumpWidget(wrap(const ArDriveNotice(
      type: ArDriveNoticeType.info,
      message: 'Searched 1 of 3 drives',
    )));

    expect(find.byType(ArDriveIcon), findsOneWidget);
    expect(find.byType(ArDriveSpinner), findsNothing);
  });
}

import 'package:ardrive/components/list_page/list_page_layout.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The body Account and security, Billing and Settings share on desktop.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    bool capWidth = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ArDriveApp(
        themeData: lightTheme(),
        builder: (context) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en', '')],
          theme: ArDriveTheme.of(context).themeData.materialThemeData,
          home: Scaffold(
            body: ReadablePageBody(
              title: 'Title',
              capWidth: capWidth,
              child: const SizedBox(
                key: Key('content'),
                width: double.infinity,
                height: 100,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('content is 880 px wide on a 1400 px window, under the title',
      (tester) async {
    await pump(tester, size: const Size(1400, 900));

    final content = find.byKey(const Key('content'));
    expect(pageContentMaxWidth, 880);
    expect(tester.getSize(content).width, 880);
    // Left-aligned with the title's row, not centred.
    expect(tester.getTopLeft(content).dx, listPagePadding);
  });

  testWidgets('content takes a narrow window whole', (tester) async {
    await pump(tester, size: const Size(600, 900));

    expect(
      tester.getSize(find.byKey(const Key('content'))).width,
      600 - 2 * listPagePadding,
    );
  });

  testWidgets('a page that sizes its own sections is not capped',
      (tester) async {
    await pump(tester, size: const Size(1400, 900), capWidth: false);

    expect(
      tester.getSize(find.byKey(const Key('content'))).width,
      1400 - 2 * listPagePadding,
    );
  });
}

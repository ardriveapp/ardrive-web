import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ArDriveColorTokens> tokensUnder(
    WidgetTester tester,
    ArDriveThemeData theme,
  ) async {
    late ArDriveColorTokens tokens;
    await tester.pumpWidget(ArDriveApp(
      themeData: theme,
      builder: (context) => MaterialApp(
        home: ArDriveOnDark(
          child: Builder(builder: (context) {
            tokens = ArDriveTheme.of(context).themeData.colorTokens;
            return const SizedBox();
          }),
        ),
      ),
    ));
    return tokens;
  }

  testWidgets('gives the dark tokens in the light theme', (tester) async {
    final tokens = await tokensUnder(tester, lightTheme());

    expect(tokens.textHigh, ArDriveColorTokens.darkMode().textHigh);
    expect(tokens.strokeMid, ArDriveColorTokens.darkMode().strokeMid);
  });

  testWidgets('gives the dark tokens in the dark theme too', (tester) async {
    final dark = ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode());
    final tokens = await tokensUnder(tester, dark);

    expect(tokens.textHigh, ArDriveColorTokens.darkMode().textHigh);
  });

  // The name is no guide: a theme with light tokens and no name of its own
  // is named "dark".
  testWidgets('gives the dark tokens under a misnamed light theme',
      (tester) async {
    final tokens = await tokensUnder(
      tester,
      ArDriveThemeData(colorTokens: ArDriveColorTokens.lightMode()),
    );

    expect(tokens.textHigh, ArDriveColorTokens.darkMode().textHigh);
  });
}

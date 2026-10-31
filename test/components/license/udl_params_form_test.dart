import 'package:ardrive/components/license/udl_params_form.dart';
import 'package:ardrive/models/forms/udl.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The fee sat in a row with a 192 wide currency select and shrank to a
/// sliver on a phone.
void main() {
  Future<void> pump(WidgetTester tester, double width) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              // The dialog's padding on a phone.
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: UdlParamsForm(
                  formGroup: createUdlParamsForm(),
                  onChangeLicenseFee: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('on a phone the fee has the full width, over the currency',
      (tester) async {
    await pump(tester, 390);

    final fee = tester.getRect(find.byType(ArDriveTextFieldNew));
    expect(fee.width, greaterThan(300));
    expect(tester.getTopLeft(find.text('Currency')).dy,
        greaterThan(fee.bottom - 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a wide screen the fee and currency share a row',
      (tester) async {
    await pump(tester, 900);

    final fee = tester.getRect(find.byType(ArDriveTextFieldNew));
    expect(tester.getTopLeft(find.text('Currency')).dy, lessThan(fee.bottom));
  });
}

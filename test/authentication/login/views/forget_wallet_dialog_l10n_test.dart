import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/authentication/login/views/modals/enter_your_password_modal.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockLoginBloc extends MockBloc<LoginEvent, LoginState>
    implements LoginBloc {}

/// The dialog's text was hard-coded English. It reads from the localizations
/// now, so a Spanish app shows Spanish and an English one is unchanged.
void main() {
  Future<void> pump(WidgetTester tester, Locale locale) =>
      tester.pumpWidget(ArDriveApp(
        builder: (context) => MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ForgetWalletDialog(loginBloc: _MockLoginBloc()),
          ),
        ),
      ));

  testWidgets('shows the dialog in Spanish', (tester) async {
    await pump(tester, const Locale('es'));
    await tester.pumpAndSettle();

    expect(find.text('¿Usar otra cuenta?'), findsOneWidget);
    expect(find.text('Esto quita el monedero de este dispositivo.'),
        findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Olvidar monedero'), findsOneWidget);
    expect(find.text('Confirmar'), findsNothing);
    expect(find.text('Use a different account?'), findsNothing);
  });

  testWidgets('shows the dialog in English, its primary named for the action', (tester) async {
    await pump(tester, const Locale('en'));
    await tester.pumpAndSettle();

    expect(find.text('Use a different account?'), findsOneWidget);
    // The primary is named for what it does, not Confirm.
    expect(find.text('Forget wallet'), findsOneWidget);
    expect(find.text('This removes the wallet from this device.'),
        findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Confirm'), findsNothing);
  });
}

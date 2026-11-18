import 'package:ardrive/user/download_wallet/bloc/download_wallet_bloc.dart';
import 'package:ardrive/user/download_wallet/download_wallet_modal.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBloc extends MockBloc<DownloadWalletEvent, DownloadWalletState>
    implements DownloadWalletBloc {}

/// The keyfile download says what went wrong in its own dialog: a wrong
/// password under the field, a failure as a notice, never a second dialog.
void main() {
  late _MockBloc bloc;
  setUpAll(() => registerFallbackValue(const DownloadWallet('')));
  Future<void> pump(WidgetTester tester, DownloadWalletState state) async {
    bloc = _MockBloc();
    whenListen(bloc, const Stream<DownloadWalletState>.empty(),
        initialState: state);
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BlocProvider<DownloadWalletBloc>.value(
            value: bloc,
            child: const DownloadWalletModal(),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('names the action Download, and the field Password',
      (tester) async {
    await pump(tester, DownloadWalletInitial());

    expect(find.widgetWithText(ArDriveButtonNew, 'Download'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Enter'), findsNothing);
  });

  testWidgets('a wrong password is the field error', (tester) async {
    await pump(tester, DownloadWalletWrongPassword());

    expect(find.text('This password is incorrect.'), findsOneWidget);
    expect(find.byType(ArDriveNotice), findsNothing);
  });

  testWidgets('a failure is a notice in the dialog, with Try again',
      (tester) async {
    await pump(tester, DownloadWalletFailure());

    expect(find.byType(ArDriveNotice), findsOneWidget);
    expect(find.widgetWithText(ArDriveButtonNew, 'Try again'), findsOneWidget);
    // One dialog: no second one titled Error on top.
    expect(find.byType(ArDriveStandardModalNew), findsOneWidget);
    expect(find.text('Error'), findsNothing);
  });

  testWidgets('two fast presses of Download ask for one download',
      (tester) async {
    await pump(tester, DownloadWalletInitial());
    await tester.enterText(find.byType(TextField), 'a password');

    final download = find.widgetWithText(ArDriveButtonNew, 'Download');
    await tester.tap(download);
    // The bloc has not shown its busy state yet.
    await tester.tap(download, warnIfMissed: false);
    await tester.pump();

    verify(() => bloc.add(any(that: isA<DownloadWallet>()))).called(1);
  });
}

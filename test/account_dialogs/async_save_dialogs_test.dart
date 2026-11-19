import 'dart:async';

import 'package:ardrive/components/turbo_url_dialog.dart';
import 'package:ardrive/user/download_wallet/bloc/download_wallet_bloc.dart';
import 'package:ardrive/user/download_wallet/download_wallet_modal.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockDownloadBloc
    extends MockBloc<DownloadWalletEvent, DownloadWalletState>
    implements DownloadWalletBloc {}

/// A save that takes time keeps its dialog open and busy until it finishes,
/// and says so in the dialog when it fails; Back waits while work runs.
void main() {
  Future<void> openTurbo(
    WidgetTester tester,
    FutureOr<void> Function(String, String) onSave,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => Material(
                  type: MaterialType.transparency,
                  child: TurboUrlDialog(
                    initialUploadUrl: 'https://upload.example.com',
                    initialPaymentUrl: 'https://payment.example.com',
                    onSave: onSave,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a slow save keeps the dialog open and busy, then closes it',
      (tester) async {
    final done = Completer<void>();
    var calls = 0;
    await openTurbo(tester, (_, __) {
      calls++;
      return done.future;
    });

    final save = find.widgetWithText(ArDriveButtonNew, 'Save');
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await tester.pump();

    expect(calls, 1);
    expect(find.byType(TurboUrlDialog), findsOneWidget);

    done.complete();
    await tester.pumpAndSettle();
    expect(find.byType(TurboUrlDialog), findsNothing);
  });

  testWidgets('a failed save stays open with the error in the dialog',
      (tester) async {
    await openTurbo(tester, (_, __) async => throw Exception('no'));

    await tester.tap(find.widgetWithText(ArDriveButtonNew, 'Save'));
    await tester.pumpAndSettle();

    expect(find.byType(TurboUrlDialog), findsOneWidget);
    expect(find.text('Couldn\'t save. Try again.'), findsOneWidget);
  });

  testWidgets('system Back waits while the keyfile downloads', (tester) async {
    final bloc = _MockDownloadBloc();
    whenListen(bloc, const Stream<DownloadWalletState>.empty(),
        initialState: DownloadWalletLoading());
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

    final pop = tester.widget<PopScope>(find.byType(PopScope).first);
    expect(pop.canPop, isFalse);
  });
}

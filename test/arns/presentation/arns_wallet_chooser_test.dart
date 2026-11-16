import 'dart:async';

import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_chooser.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockWalletCubit extends MockCubit<ArNSWalletState>
    implements ArNSWalletCubit {}

void main() {
  group('walletBrowseTarget', () {
    // A shared private drive link keeps its key in the address bar.
    final base = Uri.parse(
      'https://app.ardrive.io/#/drives/abc?name=Docs&driveKey=SECRET',
    );

    test('sends a wallet browser only the origin on the web', () {
      final target = walletBrowseTarget(base, isWeb: true);

      expect(target, 'https://app.ardrive.io');
      expect(phantomBrowseUrl(target), isNot(contains('SECRET')));
      expect(solflareBrowseUrl(target), isNot(contains('SECRET')));
    });

    test('keeps the app address off the web', () {
      expect(walletBrowseTarget(base, isWeb: false), 'https://app.ardrive.io');
    });
  });

  group('a rejected connect', () {
    const message = 'Not connected. Try again or choose another wallet.';
    late _MockWalletCubit cubit;

    setUp(() {
      cubit = _MockWalletCubit();
      whenListen(
        cubit,
        const Stream<ArNSWalletState>.empty(),
        initialState: const ArNSWalletState(
          enabled: true,
          profileAddress: 'profile',
          installedWallets: [SolanaWalletInfo(name: 'Phantom', icon: '')],
        ),
      );
    });

    Future<void> pump(WidgetTester tester) => tester.pumpWidget(
          ArDriveApp(
            themeData: lightTheme(),
            builder: (context) => MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: BlocProvider<ArNSWalletCubit>.value(
                value: cubit,
                child: const Scaffold(body: ArNSWalletChooser()),
              ),
            ),
          ),
        );

    testWidgets('says so, and clears on the next attempt', (tester) async {
      when(() => cubit.link(any()))
          .thenAnswer((_) async => throw Exception('User rejected'));
      await pump(tester);
      expect(find.text(message), findsNothing);

      await tester.tap(find.text('Phantom'));
      await tester.pump();
      expect(find.text(message), findsOneWidget);

      // The next attempt hangs on the wallet's prompt: the message is gone.
      final prompt = Completer<void>();
      when(() => cubit.link(any())).thenAnswer((_) => prompt.future);
      await tester.tap(find.text('Phantom'));
      await tester.pump();
      expect(find.text(message), findsNothing);

      prompt.completeError(Exception('User rejected'));
      await tester.pump();
      expect(find.text(message), findsOneWidget);
    });

    testWidgets('is not shown when the connect works', (tester) async {
      when(() => cubit.link(any())).thenAnswer((_) async {});
      await pump(tester);

      await tester.tap(find.text('Phantom'));
      await tester.pump();

      expect(find.text(message), findsNothing);
    });
  });
}

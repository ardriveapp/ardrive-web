import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/pages/raw_transaction_view/raw_transaction_content.dart';
import 'package:ardrive/pages/raw_transaction_view/raw_transaction_view_cubit.dart';
import 'package:ardrive/pages/raw_transaction_view/raw_transaction_view_page.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRawTransactionViewCubit extends MockCubit<RawTransactionViewState>
    implements RawTransactionViewCubit {}

/// The `/view/{txId}` page as a reader meets it.
///
/// Same state machine as the recipient page (`§2` of the plan) minus `LOCKED`
/// and minus freshness: a transaction is immutable and this route serves public
/// content only.
void main() {
  const txId = 'j48SFG4GgnFej4tCqKU2iUgI4alFArg_8o8pVLiGujI';
  const sandboxUrl =
      'https://r6hrefdoa2bhcxuprnbkrjjwrfearynjiublqp7sr4uvjoegxiza'
      '.arweave.net/$txId';

  late MockRawTransactionViewCubit cubit;
  late StreamController<RawTransactionViewState> states;

  RawTransactionReady ready({String? name = 'notes.txt'}) {
    final bytes = Uint8List.fromList(utf8.encode('a plain little file'));
    final presentation = decidePresentation(
      claimedContentType: 'text/plain',
      sniff: sniffTransactionContent(bytes),
    );

    return RawTransactionReady(
      txId: txId,
      presentation: presentation,
      sandboxUrl: sandboxUrl,
      name: name,
      size: 19,
      ownerAddress: 'Zvp8dEkO3nQ2wX9yV8uT7sR6qP5oN4mL3kJ2iH1gF0e',
      bytes: bytes,
      text: 'a plain little file',
    );
  }

  Widget wrap(Widget child) {
    return ArDriveTheme(
      themeData: lightTheme(),
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', '')],
        home: child,
      ),
    );
  }

  Future<void> pumpPage(
    WidgetTester tester,
    RawTransactionViewState initialState,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    whenListen(cubit, states.stream, initialState: initialState);

    await tester.pumpWidget(
      wrap(
        BlocProvider<RawTransactionViewCubit>.value(
          value: cubit,
          child: const RawTransactionViewBody(),
        ),
      ),
    );
    await tester.pump();
  }

  setUp(() {
    cubit = MockRawTransactionViewCubit();
    states = StreamController<RawTransactionViewState>.broadcast();

    when(() => cubit.retry()).thenAnswer((_) async {});
  });

  tearDown(() async {
    await states.close();
  });

  testWidgets('RESOLVING shows the link\'s own hints while it waits',
      (tester) async {
    await pumpPage(
      tester,
      const RawTransactionLoadInProgress(
        name: 'talk.mp4',
        contentType: 'video/mp4',
      ),
    );

    expect(find.text('talk.mp4'), findsOneWidget);
    expect(find.textContaining('Loading'), findsOneWidget);
  });

  testWidgets('READY leads with the file and one obvious download',
      (tester) async {
    await pumpPage(tester, ready());

    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('READY keeps the transaction id out of the reader\'s face',
      (tester) async {
    await pumpPage(tester, ready());

    // Folded into the details drawer (review F18), not printed on the card.
    expect(find.text(txId), findsNothing);
    expect(find.text('File details'), findsOneWidget);
  });

  testWidgets('READY still has a title when the transaction never had a name',
      (tester) async {
    await pumpPage(tester, ready(name: null));

    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('a malformed transaction id is a damaged link, not a 404',
      (tester) async {
    await pumpPage(tester, const RawTransactionLinkDamaged());

    // Nothing to retry: only whoever sent the link can fix it.
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Download'), findsNothing);
  });

  testWidgets('NOT_FOUND offers another attempt', (tester) async {
    await pumpPage(tester, const RawTransactionNotFound());

    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();

    verify(() => cubit.retry()).called(1);
  });

  testWidgets('ERROR_NETWORK offers another attempt', (tester) async {
    await pumpPage(tester, const RawTransactionLoadFailure());

    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();

    verify(() => cubit.retry()).called(1);
  });
}

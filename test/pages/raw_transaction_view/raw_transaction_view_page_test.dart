import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/pages/raw_transaction_view/raw_transaction_content.dart';
import 'package:ardrive/pages/raw_transaction_view/raw_transaction_view_cubit.dart';
import 'package:ardrive/pages/raw_transaction_view/raw_transaction_view_page.dart';
import 'package:ardrive/pages/shared_file/shared_file_frame.dart';
import 'package:ardrive/pages/shared_file/shared_file_ready_layout.dart';
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

  const ownerAddress = 'Zvp8dEkO3nQ2wX9yV8uT7sR6qP5oN4mL3kJ2iH1gF0e';

  /// Wide enough for the desktop layout, and for the phone column.
  const wide = Size(1440, 2000);
  const narrow = Size(800, 2000);

  RawTransactionReady ready({
    String? name = 'notes.txt',
    String? owner = ownerAddress,
  }) {
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
      ownerAddress: owner,
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
    RawTransactionViewState initialState, {
    Size size = narrow,
  }) async {
    tester.view.physicalSize = size;
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

  testWidgets('READY calls a nameless transaction what it is', (tester) async {
    await pumpPage(tester, ready(name: null));

    // Not the share page's "Shared file": nobody shared a file here. (The
    // preview captions the text with the same title.)
    expect(find.text('Arweave transaction'), findsWidgets);
    expect(find.text('Shared file'), findsNothing);
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

  /// The width the frame was told to hold the card to, which is the page's
  /// choice of layout.
  double cardWidth(WidgetTester tester) => tester
      .widget<ConstrainedBox>(find.byWidgetPredicate((w) =>
          w is ConstrainedBox &&
          (w.constraints.maxWidth == SharedFileFrame.maxContentWidth ||
              w.constraints.maxWidth == SharedFileFrame.maxWideContentWidth)))
      .constraints
      .maxWidth;

  group('the same card as the share page', () {
    testWidgets('READY on a desktop is the wide card: header, pane, panel',
        (tester) async {
      await pumpPage(tester, ready(), size: wide);

      final pane = find.byKey(rawTransactionPreviewPaneKey);
      expect(pane, findsOneWidget);
      expect(
        tester.getSize(pane).height,
        SharedFileReadyLayout.previewPaneHeight,
      );

      // Download sits in the header, beside what the thing is, not under it,
      // and above the pane.
      final name = tester.getRect(find.text('notes.txt'));
      final download = tester.getRect(find.text('Download'));
      expect(download.left, greaterThan(name.right));
      expect(download.bottom, lessThan(tester.getRect(pane).top));
      expect(cardWidth(tester), SharedFileFrame.maxWideContentWidth);

      // The details sit beside the pane, not under it.
      final details = tester.getRect(find.text('File details'));
      expect(details.left, greaterThan(tester.getRect(pane).right));
    });

    testWidgets('READY on a phone is the column, with no pane', (tester) async {
      await pumpPage(tester, ready());

      expect(find.byKey(rawTransactionPreviewPaneKey), findsNothing);
      expect(
        cardWidth(tester),
        lessThanOrEqualTo(SharedFileFrame.maxContentWidth),
      );

      // Download spans the column, under the name.
      final name = tester.getRect(find.text('notes.txt'));
      final download = tester.getRect(find.widgetWithText(
        ArDriveButton,
        'Download',
      ));
      expect(download.top, greaterThan(name.bottom));
      expect(download.width, greaterThan(300));
    });

    for (final entry in {
      'RESOLVING': const RawTransactionLoadInProgress(name: 'talk.mp4'),
      'ERROR_LINK': const RawTransactionLinkDamaged(),
      'NOT_FOUND': const RawTransactionNotFound(),
      'ERROR_NETWORK': const RawTransactionLoadFailure(),
    }.entries) {
      testWidgets('${entry.key} stays narrow on a desktop', (tester) async {
        await pumpPage(tester, entry.value, size: wide);

        // Only the ready card has any use for the width; a message stretched
        // across a desktop reads worse than one in a column.
        expect(find.byKey(rawTransactionPreviewPaneKey), findsNothing);
        expect(
          cardWidth(tester),
          lessThanOrEqualTo(SharedFileFrame.maxContentWidth),
        );
      });
    }

    testWidgets('the panel is Details alone: a transaction has no versions',
        (tester) async {
      await pumpPage(tester, ready(), size: wide);

      expect(find.text('File details'), findsOneWidget);
      expect(find.text('Version history'), findsNothing);

      // The lone tab is already showing, so pressing it changes nothing.
      await tester.tap(find.text('File details'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('File type'), findsOneWidget);
    });
  });

  group('the details tab', () {
    testWidgets('leads with the type and who put it there', (tester) async {
      await pumpPage(tester, ready(), size: wide);

      expect(find.text('File type'), findsOneWidget);
      expect(find.text('text/plain'), findsWidgets);
      expect(find.text(ownerAddress), findsOneWidget);
    });

    testWidgets('keeps the transaction id one step further in',
        (tester) async {
      await pumpPage(tester, ready(), size: wide);

      expect(find.text(txId), findsNothing);

      await tester.tap(find.text('Transaction details'));
      await tester.pump();

      expect(find.text(txId), findsOneWidget);
    });

    testWidgets('says nothing about an owner it does not know',
        (tester) async {
      await pumpPage(tester, ready(owner: null), size: wide);

      expect(find.text('Shared by'), findsNothing);
      expect(find.text('File type'), findsOneWidget);
    });
  });

  group('the pane holds whatever the transaction is', () {
    Future<void> pumpReady(WidgetTester tester, Widget preview) async {
      tester.view.physicalSize = wide;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        wrap(
          // The page supplies the Material; the view alone does not.
          Material(
            child: SingleChildScrollView(
              child: SizedBox(
                width: SharedFileFrame.maxWideContentWidth,
                child: RawTransactionReadyView(
                  state: ready(),
                  isWide: true,
                  preview: preview,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('a preview taller than the pane scrolls instead of overflowing',
        (tester) async {
      // A contradicted type, a sandbox note, 360px of content and an offer to
      // open it elsewhere, all at once, is taller than the pane.
      await pumpReady(
        tester,
        const SizedBox(key: Key('tallPreview'), height: 900),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(rawTransactionPreviewPaneKey)).height,
        SharedFileReadyLayout.previewPaneHeight,
      );

      // And the part below the fold is reachable.
      final scrollable = find.descendant(
        of: find.byKey(rawTransactionPreviewPaneKey),
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsOneWidget);
      await tester.drag(scrollable, const Offset(0, -600));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a short preview sits in the middle of the pane',
        (tester) async {
      await pumpReady(
        tester,
        const SizedBox(key: Key('shortPreview'), height: 40, width: 40),
      );

      final pane = tester.getRect(find.byKey(rawTransactionPreviewPaneKey));
      final preview = tester.getRect(find.byKey(const Key('shortPreview')));

      expect(preview.center.dy, closeTo(pane.center.dy, 1));
      expect(preview.center.dx, closeTo(pane.center.dx, 1));
    });
  });
}

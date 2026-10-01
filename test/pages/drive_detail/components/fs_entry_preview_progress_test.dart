import 'package:ardrive/blocs/fs_entry_preview/fs_entry_preview_cubit.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart'
    show
        FsEntryPreviewFailedMessage,
        FsEntryPreviewOnRequestPrompt,
        FsEntryPreviewProgress,
        FsEntryPreviewWidget;
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFsEntryPreviewCubit extends MockCubit<FsEntryPreviewState>
    implements FsEntryPreviewCubit {}

/// What the reader sees while a preview arrives, and when it does not (#2206).
void main() {
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
        home: Material(child: Center(child: child)),
      ),
    );
  }

  group('while it arrives', () {
    testWidgets('a declared length is a bar, and how much of how much',
        (tester) async {
      const received = 18 * 1024 * 1024;
      const total = 47 * 1024 * 1024;

      await tester.pumpWidget(wrap(const FsEntryPreviewProgress(
        state: FsEntryPreviewLoading(received: received, total: total),
      )));

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(received / total, 0.0001));
      expect(
        find.text('${filesize(received)} of ${filesize(total)}'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('no declared length is a spinner and a running count',
        (tester) async {
      const received = 3 * 1024 * 1024;

      await tester.pumpWidget(wrap(const FsEntryPreviewProgress(
        state: FsEntryPreviewLoading(received: received),
      )));

      expect(find.byType(LinearProgressIndicator), findsNothing,
          reason: 'a bar with nothing to measure against would be a guess');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(filesize(received)), findsOneWidget);
    });

    testWidgets('before a byte has come, it says it is downloading',
        (tester) async {
      await tester.pumpWidget(wrap(const FsEntryPreviewProgress(
        state: FsEntryPreviewLoading(),
      )));

      expect(find.text('Downloading...'), findsOneWidget);
    });

    testWidgets(
        'once the bytes are in, it says it is decrypting, without a bar',
        (tester) async {
      await tester.pumpWidget(wrap(const FsEntryPreviewProgress(
        state: FsEntryPreviewLoading(
          phase: FsEntryPreviewLoadPhase.decrypting,
          received: 100,
          total: 100,
        ),
      )));

      expect(find.text('Decrypting...'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('when it does not arrive', () {
    testWidgets('a download that failed says so, and offers another try',
        (tester) async {
      var retries = 0;

      await tester.pumpWidget(wrap(FsEntryPreviewFailedMessage(
        state: const FsEntryPreviewFailed(FsEntryPreviewFailure.download),
        onRetry: () => retries++,
      )));

      expect(find.text("The preview couldn't be downloaded."), findsOneWidget);

      await tester.tap(find.text('Try Again'));
      await tester.pump();

      expect(retries, 1);
    });

    testWidgets('bytes that would not decrypt offer no retry that cannot help',
        (tester) async {
      await tester.pumpWidget(wrap(FsEntryPreviewFailedMessage(
        state: const FsEntryPreviewFailed(FsEntryPreviewFailure.decrypt),
        onRetry: () => fail('decryption must not offer a retry'),
      )));

      expect(
        find.textContaining("couldn't be decrypted for preview"),
        findsOneWidget,
      );
      expect(find.text('Try Again'), findsNothing);
    });
  });

  group('a large file waits to be asked for', () {
    testWidgets('says what Preview will download, and asks', (tester) async {
      const size = 47 * 1024 * 1024;
      var asked = 0;

      await tester.pumpWidget(wrap(FsEntryPreviewOnRequestPrompt(
        state: const FsEntryPreviewOnRequest(size: size),
        onPreview: () => asked++,
      )));

      expect(
        find.text('This file is ${filesize(size)}. '
            'Previewing it downloads the whole file.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Preview'));
      await tester.pump();

      expect(asked, 1);
    });
  });

  group('inside the preview', () {
    late _MockFsEntryPreviewCubit cubit;

    setUp(() {
      cubit = _MockFsEntryPreviewCubit();
      when(() => cubit.retry()).thenAnswer((_) async {});
      when(() => cubit.loadOnRequest()).thenAnswer((_) async {});
    });

    Future<void> pumpPreview(
      WidgetTester tester,
      FsEntryPreviewState state,
    ) async {
      whenListen(cubit, const Stream<FsEntryPreviewState>.empty(),
          initialState: state);

      await tester.pumpWidget(wrap(SizedBox(
        width: 400,
        height: 400,
        child: FsEntryPreviewWidget(
          state: state,
          isSharePage: false,
          canNavigateThroughImages: false,
          previewCubit: cubit,
        ),
      )));
    }

    testWidgets('a loading preview shows its progress', (tester) async {
      await pumpPreview(
        tester,
        const FsEntryPreviewLoading(received: 50, total: 100),
      );

      expect(find.byType(FsEntryPreviewProgress), findsOneWidget);
    });

    testWidgets('Try Again asks the cubit, not the page', (tester) async {
      await pumpPreview(
        tester,
        const FsEntryPreviewFailed(FsEntryPreviewFailure.download),
      );

      await tester.tap(find.text('Try Again'));
      await tester.pump();

      verify(() => cubit.retry()).called(1);
    });

    testWidgets('Preview on a large file asks the cubit', (tester) async {
      await pumpPreview(
        tester,
        const FsEntryPreviewOnRequest(size: 30 * 1024 * 1024),
      );

      await tester.tap(find.text('Preview'));
      await tester.pump();

      verify(() => cubit.loadOnRequest()).called(1);
    });

    testWidgets('a failure is not dressed up as "unavailable"', (tester) async {
      await pumpPreview(
        tester,
        const FsEntryPreviewFailed(FsEntryPreviewFailure.download),
      );

      expect(find.text('Preview unavailable'), findsNothing);
      expect(find.byType(FsEntryPreviewFailedMessage), findsOneWidget);
    });
  });
}

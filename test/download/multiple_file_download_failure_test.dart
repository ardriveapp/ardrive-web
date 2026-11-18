import 'package:ardrive/blocs/file_download/file_download_cubit.dart';
import 'package:ardrive/download/multiple_download_bloc.dart';
import 'package:ardrive/download/multiple_file_download_modal.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBloc extends MockBloc<MultipleDownloadEvent, MultipleDownloadState>
    implements MultipleDownloadBloc {}

/// A failed multi-file download says what failed, and offers Cancel, Skip and
/// Try again, with Try again last as the primary: Skip drops a file, so it is
/// never the main button.
void main() {
  late _MockBloc bloc;

  setUpAll(() => registerFallbackValue(const ResumeDownload()));

  Future<void> open(
    WidgetTester tester,
    FileDownloadFailureReason reason,
  ) async {
    bloc = _MockBloc();
    whenListen(
      bloc,
      const Stream<MultipleDownloadState>.empty(),
      initialState: MultipleDownloadFailure(reason),
    );
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BlocProvider<MultipleDownloadBloc>.value(
              value: bloc,
              child: const MultipleFilesDownload(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  ArDriveButtonNew button(WidgetTester tester, String text) => tester
      .widget<ArDriveButtonNew>(find.widgetWithText(ArDriveButtonNew, text));

  testWidgets('Try again is the primary and Skip is not', (tester) async {
    await open(tester, FileDownloadFailureReason.networkConnectionError);

    expect(find.text('File download failed'), findsOneWidget);
    expect(find.byType(ArDriveNotice), findsOneWidget);
    expect(button(tester, 'Try again').variant, ButtonVariant.primary);
    expect(button(tester, 'Skip').variant, ButtonVariant.secondary);
    expect(button(tester, 'Cancel').variant, ButtonVariant.secondary);

    final labels = tester
        .widgetList<ArDriveButtonNew>(find.byType(ArDriveButtonNew))
        .map((b) => b.text)
        .toList();
    expect(labels, ['Cancel', 'Skip', 'Try again']);
  });

  testWidgets('a file above the limit offers only a way out', (tester) async {
    await open(tester, FileDownloadFailureReason.fileAboveLimit);

    expect(
        find.text('This file is too large to download here'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Skip'), findsNothing);
  });

  testWidgets('Try again resumes', (tester) async {
    await open(tester, FileDownloadFailureReason.unknownError);

    await tester.tap(find.text('Try again'));
    verify(() => bloc.add(const ResumeDownload())).called(1);
  });
}

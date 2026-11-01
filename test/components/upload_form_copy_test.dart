import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/components/upload_form.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockUploadCubit extends MockCubit<UploadState> implements UploadCubit {}

class _MockUploadController extends Mock implements UploadController {}

/// What the upload dialogs say about money and about canceling.
void main() {
  late _MockUploadCubit cubit;

  setUp(() {
    cubit = _MockUploadCubit();
    when(() => cubit.lastReadyState).thenReturn(null);
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
          home: ChangeNotifierProvider<ActivityTracker>(
            create: (_) => ActivityTracker(),
            child: BlocProvider<UploadCubit>.value(
              value: cubit,
              child: Scaffold(body: Center(child: child)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a failed upload says whether money moved', (tester) async {
    await pump(
      tester,
      UploadFailureWidget(state: UploadFailure(error: UploadErrors.unknown)),
    );

    expect(find.textContaining('Files that finished uploading were paid for'),
        findsOneWidget);
    expect(find.textContaining('The rest were not'), findsOneWidget);
  });

  testWidgets('canceling asks a real question, and keeping is the primary',
      (tester) async {
    final state = UploadInProgress(
      progress: UploadProgress(
        progressInPercentage: 0.5,
        totalSize: 100,
        tasks: const {},
        totalUploaded: 50,
        numberOfItems: 1,
        numberOfUploadedItems: 0,
        hasUploadInProgress: true,
      ),
      totalProgress: 0.5,
      controller: _MockUploadController(),
      uploadMethod: UploadMethod.ar,
    );
    when(() => cubit.state).thenReturn(state);
    await pump(
      tester,
      UploadInProgressWidget(state: state, onChangeCancelWarning: (_) {}),
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Cancel this upload?'), findsOneWidget);
    expect(find.text('Warning'), findsNothing);

    ArDriveButtonNew button(String label) => tester.widget<ArDriveButtonNew>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(ArDriveButtonNew),
          ),
        );
    expect(button('Keep uploading').variant, ButtonVariant.primary);
    expect(button('Cancel upload').variant, ButtonVariant.secondary);
  });
}

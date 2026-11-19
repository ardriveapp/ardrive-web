import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/blocs/hide/hide_bloc.dart';
import 'package:ardrive/blocs/hide/hide_event.dart';
import 'package:ardrive/blocs/hide/hide_state.dart';
import 'package:ardrive/components/hide_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockHideBloc extends MockBloc<HideEvent, HideState>
    implements HideBloc {}

class _MockGlobalHideBloc extends MockBloc<GlobalHideEvent, GlobalHideState>
    implements GlobalHideBloc {}

class _MockDriveDetailCubit extends MockCubit<DriveDetailState>
    implements DriveDetailCubit {}

/// A hide that failed says what happened and what to do, and offers to run
/// again, instead of repeating its title.
void main() {
  Future<void> pump(
    WidgetTester tester,
    HideAction action, {
    VoidCallback? onRetry,
  }) async {
    final hideBloc = _MockHideBloc();
    whenListen(
      hideBloc,
      const Stream<HideState>.empty(),
      initialState: FailureHideState(hideAction: action),
    );
    final globalHide = _MockGlobalHideBloc();
    when(() => globalHide.state)
        .thenReturn(const GlobalHideInitial(userHasHiddenDrive: false));
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<HideBloc>.value(value: hideBloc),
          BlocProvider<GlobalHideBloc>.value(value: globalHide),
        ],
        child: ArDriveTheme(
          themeData: lightTheme(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: HideDialog(
                driveDetailCubit: _MockDriveDetailCubit(),
                onRetry: onRetry,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the failure says what to do, in a notice', (tester) async {
    await pump(tester, HideAction.hideFile);

    expect(find.text('Failed to hide file'), findsOneWidget);
    expect(find.byType(ArDriveNotice), findsOneWidget);
    expect(find.textContaining('check your connection'), findsOneWidget);
  });

  testWidgets('the drive variants are localised titles', (tester) async {
    await pump(tester, HideAction.hideDrive);
    expect(find.text('Failed to hide drive'), findsOneWidget);

    await pump(tester, HideAction.unhideDrive);
    expect(find.text('Failed to unhide drive'), findsOneWidget);
  });

  testWidgets('Try again runs the hide again; Close does not', (tester) async {
    var retried = 0;
    await pump(tester, HideAction.hideFile, onRetry: () => retried++);

    expect(
      tester
          .widget<ArDriveButtonNew>(
              find.widgetWithText(ArDriveButtonNew, 'Close'))
          .variant,
      ButtonVariant.secondary,
    );
    await tester.tap(find.text('Try again'));
    expect(retried, 1);
  });
}

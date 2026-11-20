import 'package:ardrive/gallery/thumbnails/make_thumbnails_cubit.dart';
import 'package:ardrive/gallery/thumbnails/make_thumbnails_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCubit extends MockCubit<MakeThumbnailsState>
    implements MakeThumbnailsCubit {}

void main() {
  late _MockCubit cubit;

  setUp(() => cubit = _MockCubit());

  Future<void> show(WidgetTester tester, MakeThumbnailsState state,
      {VoidCallback? onMade}) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    when(() => cubit.state).thenReturn(state);
    await tester.pumpWidget(ArDriveTheme(
      themeData: lightTheme(),
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BlocProvider<MakeThumbnailsCubit>.value(
            value: cubit,
            child: MakeThumbnailsDialog(
              folderName: 'Trips',
              isPrivate: false,
              onMade: onMade,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  ArDriveButtonNew button(WidgetTester tester, String text) =>
      tester.widget<ArDriveButtonNew>(find
          .byWidgetPredicate((w) => w is ArDriveButtonNew && w.text == text));

  testWidgets('while it works: how far, and Stop', (tester) async {
    await show(
        tester,
        const MakeThumbnailsState(
            phase: MakeThumbnailsPhase.working, total: 18, made: 6));
    expect(find.text('6 of 18'), findsOneWidget);
    expect(find.text('Each one appears in the gallery as it lands.'),
        findsOneWidget);
    await tester.tap(find.text('Stop'));
    verify(() => cubit.stop()).called(1);
  });

  testWidgets('stopping: Stop is held while the last ones finish',
      (tester) async {
    await show(
        tester,
        const MakeThumbnailsState(
            phase: MakeThumbnailsPhase.stopping, total: 18, made: 6));
    expect(button(tester, 'Stop').isDisabled, isTrue);
  });

  testWidgets('each one that lands refreshes the explorer', (tester) async {
    var refreshed = 0;
    whenListen(
      cubit,
      Stream.fromIterable(const [
        MakeThumbnailsState(
            phase: MakeThumbnailsPhase.working, total: 3, made: 1),
        MakeThumbnailsState(
            phase: MakeThumbnailsPhase.working, total: 3, made: 2),
      ]),
      initialState: const MakeThumbnailsState(
          phase: MakeThumbnailsPhase.working, total: 3),
    );
    await tester.pumpWidget(const SizedBox());
    await show(tester,
        const MakeThumbnailsState(phase: MakeThumbnailsPhase.working, total: 3),
        onMade: () => refreshed++);
    await tester.pump();
    expect(refreshed, 2);
  });

  testWidgets('done: what was made, and what could not be read',
      (tester) async {
    await show(
        tester,
        const MakeThumbnailsState(
            phase: MakeThumbnailsPhase.done, total: 18, made: 16, failed: 2));
    expect(find.text('Made thumbnails for 16 images.'), findsOneWidget);
    expect(find.text('2 images could not be read. Try again later.'),
        findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('nothing to do says so', (tester) async {
    await show(tester,
        const MakeThumbnailsState(phase: MakeThumbnailsPhase.nothingToDo));
    expect(find.text('Every image here has its thumbnails.'), findsOneWidget);
  });
}

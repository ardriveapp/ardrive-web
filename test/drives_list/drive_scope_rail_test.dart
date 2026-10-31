import 'package:ardrive/drives_list/domain/drive_scope.dart';
import 'package:ardrive/drives_list/presentation/drive_scope_rail.dart';
import 'package:ardrive/drives_list/presentation/drives_list_cubit.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDrivesListCubit extends MockCubit<DrivesListState>
    implements DrivesListCubit {}

void main() {
  late _MockDrivesListCubit cubit;

  setUp(() {
    cubit = _MockDrivesListCubit();
    whenListen(
      cubit,
      const Stream<DrivesListState>.empty(),
      initialState: const DrivesListLoaded(drives: []),
    );
    when(() => cubit.showScope(any())).thenAnswer((_) async {});
  });

  setUpAll(() => registerFallbackValue(DriveScope.all));

  Widget app(Widget home) => ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
          home: BlocProvider<DrivesListCubit>.value(value: cubit, child: home),
        ),
      );

  // #108: on a phone the drawer stayed open over the list the tap changed.
  testWidgets('a scope tapped in the drawer closes the drawer', (tester) async {
    final scaffold = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(app(Scaffold(
      key: scaffold,
      drawer: const Drawer(child: DriveScopeRail(showLabels: true)),
      body: const SizedBox(),
    )));
    scaffold.currentState!.openDrawer();
    await tester.pumpAndSettle();
    expect(scaffold.currentState!.isDrawerOpen, isTrue);

    await tester.tap(find.text('Public drives'));
    await tester.pumpAndSettle();

    verify(() => cubit.showScope(DriveScope.public)).called(1);
    expect(scaffold.currentState!.isDrawerOpen, isFalse);
  });

  testWidgets('outside a drawer it only changes the scope', (tester) async {
    await tester.pumpWidget(app(const Scaffold(
      body: DriveScopeRail(showLabels: true),
    )));

    await tester.tap(find.text('Private drives'));
    await tester.pumpAndSettle();

    verify(() => cubit.showScope(DriveScope.private)).called(1);
  });

  // #86: the scope had three names; it is "Shared with me", as its row tag.
  testWidgets('the shared scope is called Shared with me', (tester) async {
    await tester.pumpWidget(app(const Scaffold(
      body: DriveScopeRail(showLabels: true),
    )));

    expect(find.text('Shared with me'), findsOneWidget);
    expect(find.text('Shared drives'), findsNothing);
  });

  // #120: ArDrive's glyphs where the icon font has them.
  test('scope icons are ArDrive glyphs where there is one', () {
    expect(DriveScopeRail.iconFor(DriveScope.public),
        ArDriveIcons.publicDrive().icon);
    expect(
        DriveScopeRail.iconFor(DriveScope.private), ArDriveIcons.lock().icon);
    expect(DriveScopeRail.iconFor(DriveScope.hidden),
        ArDriveIcons.eyeClosed().icon);
  });
}

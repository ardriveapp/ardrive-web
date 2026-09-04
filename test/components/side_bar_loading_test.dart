import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/components/side_bar.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_utils/mocks.dart';

class _MockGlobalHideBloc extends MockBloc<GlobalHideEvent, GlobalHideState>
    implements GlobalHideBloc {}

/// An empty nav is indistinguishable from a wallet that has no drives - and
/// that is exactly what a returning user sees on a device the app has not read
/// yet. The real sidebar is mounted here, not a copy of its logic.
void main() {
  late MockDrivesCubit drivesCubit;
  late MockProfileCubit profileCubit;
  late MockDriveDetailCubit driveDetailCubit;
  late _MockGlobalHideBloc hideBloc;

  setUp(() {
    drivesCubit = MockDrivesCubit();
    profileCubit = MockProfileCubit();
    driveDetailCubit = MockDriveDetailCubit();
    hideBloc = _MockGlobalHideBloc();

    whenListen(profileCubit, const Stream<ProfileState>.empty(),
        initialState: ProfileCheckingAvailability());
    whenListen(driveDetailCubit, const Stream<DriveDetailState>.empty(),
        initialState: DriveDetailLoadInProgress());
    whenListen(hideBloc, const Stream<GlobalHideState>.empty(),
        initialState: const HiddingItems(userHasHiddenDrive: false));
  });

  Widget wrap(DrivesState drivesState) {
    whenListen(drivesCubit, const Stream<DrivesState>.empty(),
        initialState: drivesState);

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
        home: MultiBlocProvider(
          providers: [
            BlocProvider<DrivesCubit>.value(value: drivesCubit),
            BlocProvider<ProfileCubit>.value(value: profileCubit),
            BlocProvider<DriveDetailCubit>.value(value: driveDetailCubit),
            BlocProvider<GlobalHideBloc>.value(value: hideBloc),
          ],
          child: const Scaffold(body: AppSideBar()),
        ),
      ),
    );
  }

  testWidgets('says it is still looking rather than showing nothing',
      (tester) async {
    await tester.pumpWidget(wrap(DrivesLoadInProgress()));
    await tester.pump();

    expect(find.text('Loading your drives...'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('says nothing once the list has actually been read',
      (tester) async {
    await tester.pumpWidget(
      wrap(DrivesLoadedWithNoDrivesFound(canCreateNewDrive: true)),
    );
    await tester.pump();

    // A genuinely empty account is the one case where silence is right: the
    // main panel carries the Getting Started story.
    expect(find.text('Loading your drives...'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}

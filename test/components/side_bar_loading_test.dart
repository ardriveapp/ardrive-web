import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/components/side_bar.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

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
        home: MultiProvider(
          providers: [
            // The sidebar reads the router to know whether the drives list is
            // the page in view, so it needs one to build at all - not only to
            // navigate.
            ListenableProvider<AppRouterDelegate>.value(
              value: AppRouterDelegate(),
            ),
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

  Drive publicDrive(String id) => Drive(
        id: id,
        rootFolderId: '$id-root',
        ownerAddress: 'me',
        name: id,
        privacy: DrivePrivacyTag.public,
        isHidden: false,
        dateCreated: DateTime(2024, 3, 4),
        lastUpdated: DateTime(2024, 3, 4),
      );

  DrivesLoadSuccess withDrives(List<Drive> drives, {String? selected}) =>
      DrivesLoadSuccess(
        selectedDriveId: selected,
        userDrives: drives,
        sharedDrives: const [],
        drivesWithAlerts: const [],
        canCreateNewDrive: true,
      );

  /// The nav has to scroll when it holds more drives than the window.
  ///
  /// Two earlier fixes did not, and both failed the same way. A scroll view
  /// hands its child an unbounded height; this column is full of Expanded,
  /// Spacer and - until this was fixed - a Flexible drive list, none of which
  /// can exceed a height they are being asked to fill. The content came out
  /// exactly as tall as the viewport however many drives there were, so there
  /// was nothing to scroll and the list below the fold was unreachable except
  /// by collapsing a section.
  ///
  /// This asserts the property that was missing rather than the widget tree
  /// that provides it: with far more drives than fit, the scrollable's extent
  /// must exceed its viewport.
  group('a drive list taller than the window', () {
    testWidgets('can actually be scrolled', (tester) async {
      tester.view.physicalSize = const Size(1200, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        wrap(
            withDrives([for (var i = 0; i < 40; i++) publicDrive('drive-$i')])),
      );
      await tester.pumpAndSettle();

      final scrollables = find.byType(Scrollable);
      expect(scrollables, findsWidgets,
          reason: 'precondition: the nav has a scroll view at all');

      // The one that actually holds the drives, whichever it is.
      final positions = tester
          .widgetList<Scrollable>(scrollables)
          .map((s) =>
              s.controller?.hasClients == true ? s.controller!.position : null)
          .whereType<ScrollPosition>()
          .toList();

      expect(
        positions.any((p) => p.maxScrollExtent > 0),
        isTrue,
        reason: 'forty drives in a 700px window must leave something below '
            'the fold to scroll to - an extent of zero is the bug: the '
            'content was made exactly as tall as the viewport',
      );
    });
  });

  /// The same property, nested the way `AppShell` actually nests it.
  ///
  /// The case above hands the sidebar a Scaffold body - a clean bounded box it
  /// will never see in the app. The real one is a Row inside a Flexible inside
  /// a Column inside a Stack, and the constraints that reach the sidebar
  /// through that are what decide whether it can scroll. A fix that works in
  /// the simpler tree and not this one is not a fix, which is how earlier
  /// attempts looked right and failed in the browser.
  testWidgets('scrolls when nested the way the app shell nests it',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    whenListen(
      drivesCubit,
      const Stream<DrivesState>.empty(),
      initialState: withDrives(
        [for (var i = 0; i < 40; i++) publicDrive('drive-$i')],
      ),
    );

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
          home: MultiProvider(
            providers: [
              ListenableProvider<AppRouterDelegate>.value(
                value: AppRouterDelegate(),
              ),
              BlocProvider<DrivesCubit>.value(value: drivesCubit),
              BlocProvider<ProfileCubit>.value(value: profileCubit),
              BlocProvider<DriveDetailCubit>.value(value: driveDetailCubit),
              BlocProvider<GlobalHideBloc>.value(value: hideBloc),
            ],
            child: Material(
              child: Stack(
                children: [
                  Column(
                    children: [
                      Flexible(
                        child: Row(
                          children: [
                            const AppSideBar(),
                            Expanded(child: Container()),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final extents = tester
        .widgetList<Scrollable>(find.byType(Scrollable))
        .map((s) => s.controller?.hasClients == true
            ? s.controller!.position.maxScrollExtent
            : null)
        .whereType<double>()
        .toList();

    expect(extents, isNotEmpty,
        reason: 'the nav must have a scroll view with a live controller');
    expect(
      extents.any((e) => e > 0),
      isTrue,
      reason: 'forty drives in a 700px window, nested as the shell nests it, '
          'must leave something below the fold',
    );
  });

  /// A drive tap has to reach whatever is on screen.
  ///
  /// On the drives list the selected drive is not what is drawn - the list is -
  /// and the tile for the drive that happened to be selected underneath it
  /// returned without selecting anything, so the tap was silent.
  group('tapping a drive', () {
    testWidgets('selects it', (tester) async {
      when(() => drivesCubit.selectDrive(any())).thenReturn(null);

      await tester.pumpWidget(
        wrap(withDrives([publicDrive('drive-a')], selected: 'drive-b')),
      );
      await tester.pump();

      await tester.tap(find.text('drive-a'));
      await tester.pump();

      verify(() => drivesCubit.selectDrive('drive-a')).called(1);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('selects it even when it is the one already selected',
        (tester) async {
      when(() => drivesCubit.selectDrive(any())).thenReturn(null);
      when(() => driveDetailCubit.openFolder()).thenAnswer((_) async {});

      await tester.pumpWidget(
        wrap(withDrives([publicDrive('drive-a')], selected: 'drive-a')),
      );
      await tester.pump();

      await tester.tap(find.text('drive-a'));
      await tester.pump();

      // The explorer still opens the drive's root folder, as it always has.
      verify(() => driveDetailCubit.openFolder()).called(1);
      verify(() => drivesCubit.selectDrive('drive-a')).called(1);

      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('says nothing at all while the list is being read',
      (tester) async {
    // The nav is where a reader looks for drives, not for a report on
    // fetching them. The surface actually waiting on the read says so - the
    // explorer's panel, the drives list, and the sync indicator, which is
    // also where the count now appears.
    await tester.pumpWidget(wrap(DrivesLoadInProgress()));
    await tester.pump();

    expect(find.text('Loading your drives...'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

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

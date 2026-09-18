import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/components/side_bar.dart';
import 'package:ardrive/drives_list/domain/drive_scope.dart';
import 'package:ardrive/drives_list/presentation/drive_scope_rail.dart';
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

import '../test_utils/fake_user.dart';
import '../test_utils/mocks.dart';

class _MockGlobalHideBloc extends MockBloc<GlobalHideEvent, GlobalHideState>
    implements GlobalHideBloc {}

Drive _drive(String id, String privacy) => Drive(
      id: id,
      rootFolderId: '$id-root',
      ownerAddress: 'me',
      name: id,
      privacy: privacy,
      isHidden: false,
      dateCreated: DateTime(2026),
      lastUpdated: DateTime(2026),
    );

/// Public, private and shared mean the same three things in both navs.
///
/// The drives list draws them with icons and the drive view drew them as three
/// plain words, so the same grouping read as two different ideas depending on
/// which screen you were on.
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
    whenListen(
      drivesCubit,
      const Stream<DrivesState>.empty(),
      initialState: DrivesLoadSuccess(
        selectedDriveId: 'photos',
        userDrives: [
          _drive('photos', DrivePrivacyTag.private),
          _drive('website', DrivePrivacyTag.public),
        ],
        sharedDrives: [_drive('shared', DrivePrivacyTag.public)],
        drivesWithAlerts: const [],
        canCreateNewDrive: true,
      ),
    );
  });

  Future<void> pumpSidebar(
    WidgetTester tester, {
    bool dark = false,
    bool loggedIn = false,
  }) async {
    if (loggedIn) {
      whenListen(
        profileCubit,
        const Stream<ProfileState>.empty(),
        initialState: ProfileLoggedIn(user: fakeUserJson, useTurbo: true),
      );
    }

    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ArDriveTheme(
        // Passing no theme data is how ArDriveTheme yields the dark theme.
        themeData: dark ? null : lightTheme(),
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
            child: const Scaffold(body: AppSideBar()),
          ),
        ),
      ),
    );

    await tester.pump();
  }

  /// Taken from the drives list's own lookup rather than written out again,
  /// so the two navs cannot drift apart.
  testWidgets('each drives heading carries the drives list icon for it',
      (tester) async {
    await pumpSidebar(tester);

    for (final scope in [
      DriveScope.public,
      DriveScope.private,
      DriveScope.sharedWithMe,
    ]) {
      expect(
        find.byIcon(DriveScopeRail.iconFor(scope)),
        findsOneWidget,
        reason: '$scope is a heading in this nav and a row in the other',
      );
    }
  });

  /// The same words, in the same case, as the rail on the drives list. They
  /// were uppercase here and title case there, which made one grouping read
  /// as two ideas depending on the screen.
  testWidgets('in the dark theme too', (tester) async {
    await pumpSidebar(tester, dark: true);

    expect(
      find.byIcon(DriveScopeRail.iconFor(DriveScope.public)),
      findsOneWidget,
    );
  });

  testWidgets('and says it the way the drives list says it', (tester) async {
    await pumpSidebar(tester);

    for (final scope in [
      DriveScope.public,
      DriveScope.private,
      DriveScope.sharedWithMe,
    ]) {
      final label = DriveScopeRail.labelFor(
        tester.element(find.byType(AppSideBar)),
        scope,
      );

      expect(find.text(label), findsOneWidget);
      expect(
        find.text(label.toUpperCase()),
        findsNothing,
        reason: 'the rail does not shout, so neither does this',
      );
    }
  });

  /// The drive view's nav on the Your Drives rail's grid. It sat 43px further
  /// in, so its headings started an icon and a gap to the right of All
  /// drives, and its drive names lined up under the headings' icons rather
  /// than their words.
  group('one grid with the rail', () {
    double left(WidgetTester tester, Finder finder) =>
        tester.getTopLeft(finder).dx;

    testWidgets('a heading starts where All drives does', (tester) async {
      await pumpSidebar(tester, loggedIn: true);

      expect(
        left(tester, find.byIcon(DriveScopeRail.iconFor(DriveScope.private))),
        left(tester, find.byIcon(DriveScopeRail.iconFor(DriveScope.all))),
      );
    });

    testWidgets("a drive's name starts where its heading's words do",
        (tester) async {
      await pumpSidebar(tester);

      final heading = DriveScopeRail.labelFor(
        tester.element(find.byType(AppSideBar)),
        DriveScope.private,
      );

      expect(
          left(tester, find.text('photos')), left(tester, find.text(heading)));
    });

    /// "Where am I" reads the same whichever nav is showing.
    testWidgets('the open drive is lit the way the rail lights a scope',
        (tester) async {
      await pumpSidebar(tester);

      DriveNavRow rowFor(String text) => tester.widget<DriveNavRow>(
            find.ancestor(
              of: find.text(text),
              matching: find.byType(DriveNavRow),
            ),
          );

      expect(rowFor('photos').isCurrent, isTrue);
      expect(rowFor('website').isCurrent, isFalse);
    });

    testWidgets('a heading folds its drives away and back', (tester) async {
      await pumpSidebar(tester);

      final heading = DriveScopeRail.labelFor(
        tester.element(find.byType(AppSideBar)),
        DriveScope.private,
      );

      await tester.tap(find.text(heading));
      await tester.pump();
      expect(find.text('photos'), findsNothing);

      await tester.tap(find.text(heading));
      await tester.pump();
      expect(find.text('photos'), findsOneWidget);
    });

    /// Hiding is something a reader does to their own drives.
    testWidgets('a drive shared with you is never drawn as hidden',
        (tester) async {
      whenListen(
        drivesCubit,
        const Stream<DrivesState>.empty(),
        initialState: DrivesLoadSuccess(
          selectedDriveId: 'photos',
          userDrives: [_drive('photos', DrivePrivacyTag.private)],
          sharedDrives: [
            _drive('shared', DrivePrivacyTag.public).copyWith(isHidden: true),
          ],
          drivesWithAlerts: const [],
          canCreateNewDrive: true,
        ),
      );
      await pumpSidebar(tester);

      final shared = tester.widget<DriveNavRow>(
        find.ancestor(
          of: find.text('shared'),
          matching: find.byType(DriveNavRow),
        ),
      );
      expect(shared.isMuted, isFalse);
    });

    /// Only the Public group used to do this; Private and Shared did nothing.
    testWidgets('clicking the open drive goes back to its root, in any group',
        (tester) async {
      when(() => driveDetailCubit.openFolder()).thenAnswer((_) async {});
      await pumpSidebar(tester);

      await tester.tap(find.text('photos'));
      await tester.pump();

      verify(() => driveDetailCubit.openFolder()).called(1);
    });
  });
}

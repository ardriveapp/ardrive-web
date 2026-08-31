import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/components/new_button/new_button.dart';
import 'package:ardrive/components/side_bar.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/app_route_path.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_utils/mocks.dart';

class _MockGlobalHideBloc extends MockBloc<GlobalHideEvent, GlobalHideState>
    implements GlobalHideBloc {}

/// The way back to the drives list, in the nav that is on screen at both
/// widths.
///
/// `showingDrivesList` was set in exactly one place - on login - so once a
/// drive had been opened the landing page was unreachable without the
/// browser's back button. The real sidebar is mounted here, against a real
/// `AppRouterDelegate`, so what the tap does is the thing the app does rather
/// than a callback a test invented.
void main() {
  const phone = Size(320, 640);
  const desktop = Size(1280, 900);

  const driveId = 'drive-1';

  late MockDrivesCubit drivesCubit;
  late MockProfileCubit profileCubit;
  late MockDriveDetailCubit driveDetailCubit;
  late _MockGlobalHideBloc hideBloc;
  late AppRouterDelegate delegate;

  Drive publicDrive(String id, String name) => Drive(
        id: id,
        rootFolderId: '$id-root',
        ownerAddress: 'me',
        name: name,
        privacy: DrivePrivacyTag.public,
        isHidden: false,
        dateCreated: DateTime(2026, 3, 4),
        lastUpdated: DateTime(2026, 3, 4),
      );

  setUp(() {
    drivesCubit = MockDrivesCubit();
    profileCubit = MockProfileCubit();
    driveDetailCubit = MockDriveDetailCubit();
    hideBloc = _MockGlobalHideBloc();
    delegate = AppRouterDelegate();

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
        selectedDriveId: driveId,
        userDrives: [
          publicDrive(driveId, 'Photos'),
          publicDrive('drive-2', 'Documents'),
        ],
        sharedDrives: const [],
        drivesWithAlerts: const [],
        canCreateNewDrive: true,
      ),
    );
  });

  /// The sidebar exactly as the app mounts it: the drawer on a phone, a column
  /// beside the page on a desktop.
  ///
  /// The size goes through both the view and MediaQuery on purpose.
  /// `setSurfaceSize` changes the box the tree is laid out in but not what
  /// MediaQuery reports, and `ScreenTypeLayout` picks its branch from
  /// MediaQuery - so a case that only set one of them would silently prove the
  /// wrong layout.
  Widget host(WidgetTester tester, {required Size size, double textScale = 1}) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

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
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              size: size,
              textScaler: TextScaler.linear(textScale),
            ),
            child: MultiProvider(
              providers: [
                ListenableProvider<AppRouterDelegate>.value(value: delegate),
              ],
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<DrivesCubit>.value(value: drivesCubit),
                  BlocProvider<ProfileCubit>.value(value: profileCubit),
                  BlocProvider<DriveDetailCubit>.value(value: driveDetailCubit),
                  BlocProvider<GlobalHideBloc>.value(value: hideBloc),
                ],
                child: size.width < 600
                    ? const Scaffold(
                        drawer: AppSideBar(),
                        body: SizedBox.expand(),
                      )
                    : const Scaffold(body: Row(children: [AppSideBar()])),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDrawer(WidgetTester tester) async {
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
  }

  /// The delegate as it is when a drive is open, which is the only state this
  /// entry exists for.
  Future<void> insideADrive() async {
    await delegate.setNewRoutePath(
      AppRoutePath.driveDetail(driveId: driveId),
    );
    delegate.onDriveSelected(driveId);
  }

  final link = find.byKey(sideBarDrivesListLinkKey);

  group('a desktop', () {
    testWidgets('offers the way back, above the drives', (tester) async {
      await insideADrive();
      await tester.pumpWidget(host(tester, size: desktop));
      await tester.pumpAndSettle();

      expect(link, findsOneWidget);
      expect(find.text('Your Drives'), findsOneWidget);

      // Above the drive list and below the New button: it is navigation, and
      // it stands over the things it contains rather than among them.
      expect(
        tester.getBottomLeft(link).dy,
        lessThanOrEqualTo(
            tester.getTopLeft(find.byType(DriveListTile).first).dy),
      );

      // And the list is still there, in full, rather than pushed out of the
      // column to make room.
      expect(find.byType(DriveListTile), findsNWidgets(2));
      expect(find.text('Photos'), findsOneWidget);
      expect(find.text('Documents'), findsOneWidget);
    });

    testWidgets('is drawn in the gap that was already there', (tester) async {
      // This column used to spend 56px on nothing between the New button and
      // the drive list. The entry is drawn in that gap - 16 above, its own
      // 25, 16 below - so the list starts a pixel from where it started
      // before, rather than in room taken away from it.
      const theGapItReplaced = 56.0;

      await insideADrive();
      await tester.pumpWidget(host(tester, size: desktop));
      await tester.pumpAndSettle();

      final newButtonBottom = tester.getBottomLeft(find.byType(NewButton)).dy;
      final driveListTop = tester.getTopLeft(find.byType(ArDriveAccordion)).dy;

      expect(
        driveListTop - newButtonBottom,
        closeTo(theGapItReplaced, 1),
        reason: 'the drive list moved by more than the gap could absorb',
      );
    });

    testWidgets('routes to the drives list, keeping the drive selected',
        (tester) async {
      await insideADrive();
      await tester.pumpWidget(host(tester, size: desktop));
      await tester.pumpAndSettle();

      expect(delegate.showingDrivesList, isFalse,
          reason: 'precondition: a drive is open');

      await tester.tap(link);
      await tester.pumpAndSettle();

      expect(delegate.showingDrivesList, isTrue);
      expect(delegate.currentConfiguration.drivesList, isTrue);
      // One tap back into the drive, because it never stopped being the
      // selected one.
      expect(delegate.driveId, driveId);
    });

    testWidgets('is still reachable on the collapsed rail', (tester) async {
      await insideADrive();
      await tester.pumpWidget(host(tester, size: desktop));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is ArDriveIconButton && w.tooltip == 'Collapse Sidebar',
        ),
      );
      await tester.pumpAndSettle();

      // No drive names at 64px wide, and no label here either - but the way
      // back cannot be one of the things that goes away.
      expect(find.byType(DriveListTile), findsNothing);
      expect(link, findsOneWidget);

      await tester.tap(link);
      await tester.pumpAndSettle();

      expect(delegate.showingDrivesList, isTrue);
    });
  });

  group('a phone', () {
    testWidgets('offers the way back in the drawer, above the drives',
        (tester) async {
      await insideADrive();
      await tester.pumpWidget(host(tester, size: phone));
      await openDrawer(tester);

      expect(link, findsOneWidget);
      expect(
        tester.getBottomLeft(link).dy,
        lessThanOrEqualTo(
            tester.getTopLeft(find.byType(DriveListTile).first).dy),
      );
      expect(find.byType(DriveListTile), findsNWidgets(2));
    });

    testWidgets('routes, and closes the drawer over what it navigated to',
        (tester) async {
      await insideADrive();
      await tester.pumpWidget(host(tester, size: phone));
      await openDrawer(tester);

      await tester.tap(link);
      await tester.pumpAndSettle();

      expect(delegate.showingDrivesList, isTrue);
      expect(delegate.driveId, driveId);
      // A drawer left open over the page it just navigated to is covering the
      // answer.
      expect(find.byKey(sideBarDrivesListLinkKey), findsNothing);
    });
  });

  for (final layout in [('a 320px phone', phone), ('a desktop', desktop)]) {
    testWidgets('${layout.$1} fits it at text scale 2.0', (tester) async {
      await insideADrive();
      await tester.pumpWidget(
        host(tester, size: layout.$2, textScale: 2),
      );

      if (layout.$2.width < 600) {
        await openDrawer(tester);
      } else {
        await tester.pumpAndSettle();
      }

      expect(tester.takeException(), isNull);

      // On screen at both ends, and drawn at the size it asked for rather
      // than quietly clipped.
      final label = find.text('Your Drives');
      expect(label, findsOneWidget);
      expect(tester.getTopLeft(label).dx, greaterThanOrEqualTo(0));
      expect(
        tester.getBottomRight(label).dx,
        lessThanOrEqualTo(layout.$2.width),
      );

      // And the drive list underneath it is still on screen.
      expect(find.byType(DriveListTile), findsNWidgets(2));
      expect(
        tester.getBottomLeft(find.byType(DriveListTile).first).dy,
        lessThanOrEqualTo(layout.$2.height),
      );
    });
  }
  testWidgets('reads in full at text scale 2.0, like the drives beneath it',
      (tester) async {
    // A single ellipsized line clipped this to "Your D..." at 2.0 while every
    // drive name under it stayed readable - the destination was the one thing
    // in the nav you could not read.
    await insideADrive();
    await tester.pumpWidget(host(tester, size: desktop, textScale: 2));
    await tester.pumpAndSettle();

    final label = tester.renderObject(
      find.descendant(
        of: find.byKey(sideBarDrivesListLinkKey),
        matching: find.text('Your Drives'),
      ),
    ) as RenderBox;

    expect(
      (label as dynamic).didExceedMaxLines,
      isFalse,
      reason: 'the nav entry clipped its own label',
    );
  });
}

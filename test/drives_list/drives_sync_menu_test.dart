import 'dart:async';

import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/drives_list/presentation/drives_sync_menu.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/mocks.dart';

class _MockProfileNameBloc extends MockBloc<ProfileNameEvent, ProfileNameState>
    implements ProfileNameBloc {}

/// The drive-wide sync actions, on the page about drives.
///
/// They used to sit behind the top bar's indicator, which was present on every
/// screen whether or not anything was happening. That indicator now appears
/// only when there is something to report, so the controls moved to the surface
/// that is always there and that lists the drives they act on.
void main() {
  late MockSyncBloc syncCubit;
  late MockDrivesCubit drivesCubit;
  late _MockProfileNameBloc profileNameBloc;
  late StreamController<SyncState> states;

  Drive drive(String id, {int lastBlockHeight = 0}) => Drive(
        id: id,
        rootFolderId: '$id-root',
        ownerAddress: 'me',
        name: id,
        privacy: 'public',
        isHidden: false,
        dateCreated: DateTime(2026, 1, 1),
        lastUpdated: DateTime(2026, 1, 1),
        lastBlockHeight: lastBlockHeight,
      );

  void withDrives(List<Drive> drives) {
    whenListen(
      drivesCubit,
      const Stream<DrivesState>.empty(),
      initialState: DrivesLoadSuccess(
        selectedDriveId: null,
        userDrives: drives,
        sharedDrives: const [],
        drivesWithAlerts: const [],
        canCreateNewDrive: true,
      ),
    );
  }

  setUpAll(() => registerFallbackValue(SyncTrigger.background));

  setUp(() {
    syncCubit = MockSyncBloc();
    drivesCubit = MockDrivesCubit();
    profileNameBloc = _MockProfileNameBloc();
    states = StreamController<SyncState>.broadcast();

    whenListen(syncCubit, states.stream, initialState: SyncIdle());
    when(() => syncCubit.syncProgress).thenReturn(SyncProgress.initial());
    when(() => syncCubit.clearErrorState()).thenReturn(null);
    when(() => syncCubit.retryFailedDrives(any())).thenAnswer((_) async {});
    when(() => syncCubit.startSync(
          deepSync: any(named: 'deepSync'),
          skipTabVisibilityCheck: any(named: 'skipTabVisibilityCheck'),
          onlyDriveIds: any(named: 'onlyDriveIds'),
          trigger: any(named: 'trigger'),
        )).thenAnswer((_) async => true);

    withDrives([drive('walked', lastBlockHeight: 12)]);
  });

  tearDown(() async => states.close());

  Widget host() => Portal(
        child: ArDriveTheme(
          themeData: lightTheme(),
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en', '')],
            home: Scaffold(
              body: MultiBlocProvider(
                providers: [
                  BlocProvider<SyncCubit>.value(value: syncCubit),
                  BlocProvider<DrivesCubit>.value(value: drivesCubit),
                  BlocProvider<ProfileNameBloc>.value(value: profileNameBloc),
                ],
                child: const Align(
                  alignment: Alignment.topRight,
                  child: DrivesSyncMenu(),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> openMenu(WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    await tester.tap(find.byType(DrivesSyncMenu));
    await tester.pump(const Duration(milliseconds: 300));
  }

  ArDriveDropdownItemTile itemNamed(WidgetTester tester, String name) =>
      tester.widget<ArDriveDropdownItemTile>(
        find.widgetWithText(ArDriveDropdownItemTile, name),
      );

  ArDriveDropdownItem entryNamed(WidgetTester tester, String name) =>
      tester.widget<ArDriveDropdownItem>(
        find.ancestor(
          of: find.widgetWithText(ArDriveDropdownItemTile, name),
          matching: find.byType(ArDriveDropdownItem),
        ),
      );

  group('what it offers', () {
    testWidgets('every drive-wide action, in one place', (tester) async {
      await openMenu(tester);

      expect(find.text('Resync'), findsOneWidget);
      expect(find.text('Deep Resync'), findsOneWidget);
      expect(find.text('Sync history'), findsOneWidget);
    });

    testWidgets('and says Sync All Drives before anything has been synced',
        (tester) async {
      // "Resync" promises a repeat of something that has not happened. On a
      // wallet where nothing has been walked it is simply the wrong word.
      withDrives([drive('never-walked')]);

      await openMenu(tester);

      expect(find.text('Sync All Drives'), findsWidgets);
      expect(find.text('Resync'), findsNothing);
    });
  });

  group('while a sync runs', () {
    setUp(() => when(() => syncCubit.state)
        .thenReturn(SyncInProgress(trigger: SyncTrigger.userInitiated)));

    testWidgets('the actions are disabled rather than silently dropped',
        (tester) async {
      // `startSync` returns immediately while one is running, so an item that
      // looks live, closes the menu and drops the request is a lie.
      whenListen(syncCubit, states.stream,
          initialState: SyncInProgress(trigger: SyncTrigger.userInitiated));

      await openMenu(tester);

      expect(itemNamed(tester, 'Resync').isDisabled, isTrue);
      expect(itemNamed(tester, 'Deep Resync').isDisabled, isTrue);
      expect(entryNamed(tester, 'Resync').onClick, isNull);
    });

    testWidgets('but the record stays reachable', (tester) async {
      // Reading what past syncs did is not an action on this one, and is most
      // wanted while a slow sync is running.
      whenListen(syncCubit, states.stream,
          initialState: SyncInProgress(trigger: SyncTrigger.userInitiated));

      await openMenu(tester);

      expect(entryNamed(tester, 'Sync history').onClick, isNotNull);
    });
  });

  group('after a sync that lost drives', () {
    testWidgets('it offers to retry exactly those drives', (tester) async {
      whenListen(
        syncCubit,
        states.stream,
        initialState: SyncCompleteWithErrors(
          failedDrives: 2,
          totalDrives: 5,
          failedDriveIds: const ['drive-a', 'drive-b'],
          errorMessages: const {},
          skippedEntityCount: 0,
          skippedEntityTxIdsByDrive: const {},
          trigger: SyncTrigger.userInitiated,
          completedAt: DateTime.now(),
        ),
      );

      await openMenu(tester);
      expect(find.text('Retry Failed'), findsOneWidget);

      entryNamed(tester, 'Retry Failed').onClick!();
      await tester.pump();

      verify(() => syncCubit.retryFailedDrives(['drive-a', 'drive-b']))
          .called(1);
    });

    testWidgets('and does not offer it when nothing failed', (tester) async {
      await openMenu(tester);

      expect(find.text('Retry Failed'), findsNothing);
    });
  });
}

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/gallery/explorer/explorer_view_mode.dart';
import 'package:ardrive/gallery/explorer/explorer_view_switch.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:drift/drift.dart' show OrderingMode;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../../test_utils/utils.dart';

class _MockSyncCubit extends MockCubit<SyncState> implements SyncCubit {}

class _MockGlobalHideBloc extends MockBloc<GlobalHideEvent, GlobalHideState>
    implements GlobalHideBloc {}

Widget _host(Widget child) => ArDriveTheme(
      themeData: lightTheme(),
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', '')],
        home: Portal(child: Scaffold(body: Center(child: child))),
      ),
    );

void main() {
  setUpAll(() => registerFallbackValue(ExplorerViewMode.list));

  group('ExplorerViewSwitch', () {
    testWidgets('names both views and marks the current one', (tester) async {
      ExplorerViewMode? picked;
      await tester.pumpWidget(_host(ExplorerViewSwitch(
        mode: ExplorerViewMode.list,
        onChanged: (m) => picked = m,
      )));
      expect(find.text('List'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);

      await tester.tap(find.text('Gallery'));
      expect(picked, ExplorerViewMode.gallery);
      picked = null;
      await tester.tap(find.text('List'));
      expect(picked, ExplorerViewMode.list);
    });

    testWidgets('on a phone one button switches to the other view',
        (tester) async {
      ExplorerViewMode? picked;
      Widget switchIn(ExplorerViewMode mode) => _host(ExplorerViewSwitch(
            compact: true,
            mode: mode,
            onChanged: (m) => picked = m,
          ));
      await tester.pumpWidget(switchIn(ExplorerViewMode.list));
      await tester
          .tap(find.byKey(const ValueKey('explorer-view-switch-compact')));
      expect(picked, ExplorerViewMode.gallery);

      await tester.pumpWidget(switchIn(ExplorerViewMode.gallery));
      await tester
          .tap(find.byKey(const ValueKey('explorer-view-switch-compact')));
      expect(picked, ExplorerViewMode.list);
    });
  });

  testWidgets(
      'a visitor to someone else\'s drive gets the switch in the phone\'s '
      'folder bar', (tester) async {
    final profileCubit = MockProfileCubit();
    final detailCubit = MockDriveDetailCubit();
    final syncCubit = _MockSyncCubit();
    final auth = MockArDriveAuth();
    final hideBloc = _MockGlobalHideBloc();
    whenListen(hideBloc, const Stream<GlobalHideState>.empty(),
        initialState: const HiddingItems(userHasHiddenDrive: false));
    when(() => auth.currentUser).thenReturn(getTestUser());
    whenListen(profileCubit, const Stream<ProfileState>.empty(),
        initialState: ProfilePromptLogIn());
    whenListen(syncCubit, const Stream<SyncState>.empty(),
        initialState: SyncIdle());

    final drive = Drive(
      id: 'drive',
      rootFolderId: 'root',
      name: 'Photos',
      ownerAddress: 'someone-else',
      dateCreated: DateTime(2026, 1, 1),
      lastUpdated: DateTime(2026, 1, 1),
      privacy: 'public',
      isHidden: false,
    );
    final root = FolderEntry(
      id: 'root',
      driveId: 'drive',
      name: 'Photos',
      path: '',
      dateCreated: DateTime(2026, 1, 1),
      lastUpdated: DateTime(2026, 1, 1),
      isGhost: false,
      isHidden: false,
    );
    var mode = ExplorerViewMode.list;
    DriveDetailLoadSuccess state() => DriveDetailLoadSuccess(
          currentDrive: drive,
          hasWritePermissions: false,
          folderInView: FolderWithContents(
              folder: root, subfolders: const [], files: const []),
          contentOrderBy: DriveOrder.name,
          contentOrderingMode: OrderingMode.asc,
          rowsPerPage: 25,
          availableRowsPerPage: const [25],
          multiselect: false,
          driveIsEmpty: false,
          selectedItem: null,
          currentFolderContents: const [],
          columnVisibility: const {},
          pathSegments: const [],
          viewMode: mode,
        );
    whenListen(detailCubit, const Stream<DriveDetailState>.empty(),
        initialState: state());
    when(() => detailCubit.setViewMode(any())).thenAnswer((_) async {});

    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      Provider<ArDriveAuth>.value(
        value: auth,
        child: MultiBlocProvider(
          providers: [
            BlocProvider<ProfileCubit>.value(value: profileCubit),
            BlocProvider<DriveDetailCubit>.value(value: detailCubit),
            BlocProvider<SyncCubit>.value(value: syncCubit),
            BlocProvider<GlobalHideBloc>.value(value: hideBloc),
          ],
          child: _host(const MobileFolderNavigation(
            driveName: 'Photos',
            isShowingHiddenFiles: false,
            isPrivate: false,
            path: [],
          )),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.byKey(const ValueKey('explorer-view-switch-compact'));
    expect(button, findsOneWidget);
    await tester.tap(button);
    verify(() => detailCubit.setViewMode(ExplorerViewMode.gallery)).called(1);
  });
}

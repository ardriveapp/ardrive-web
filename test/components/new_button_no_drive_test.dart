import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/new_button/new_button.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
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

class _Loaded extends Mock implements DriveDetailLoadSuccess {}

class _Folder extends Mock implements FolderWithContents {}

class _FolderEntry extends Mock implements FolderEntry {}

Drive _drive({required String ownerAddress, String privacy = 'private'}) =>
    Drive(
      id: 'photos',
      rootFolderId: 'root-photos',
      ownerAddress: ownerAddress,
      name: 'Photos',
      privacy: privacy,
      isHidden: false,
      dateCreated: DateTime(2026),
      lastUpdated: DateTime(2026),
    );

/// What the New menu offers with no drive open, which is what the drives list
/// is, and in a drive nothing has read yet.
///
/// Two rules are held here. On the drives list the menu is about drives:
/// uploading, which leads to the drive the files will go to, and the drive
/// actions themselves. Everything that needs a folder stays out, because
/// there is no folder in sight.
///
/// Inside a drive the menu keeps its shape whether or not the app has read
/// that drive. It used to hold a single row, "Advanced", opening onto a
/// single action, which readers took for a broken app.
void main() {
  late MockProfileCubit profileCubit;
  late MockDriveDetailCubit driveDetailCubit;
  late MockDrivesCubit drivesCubit;
  late MockSyncBloc syncCubit;
  late MockArDriveAuth auth;
  late AppRouterDelegate router;
  late MockConfigService configService;

  /// [syncingDriveId] is a sync reading that one drive.
  void syncing({String? syncingDriveId}) {
    whenListen(
      syncCubit,
      const Stream<SyncState>.empty(),
      initialState: syncingDriveId == null ? SyncIdle() : SyncInProgress(),
    );
    when(() => syncCubit.syncingDriveId).thenReturn(syncingDriveId);
    when(() => syncCubit.syncingDriveIds)
        .thenReturn(syncingDriveId == null ? null : {syncingDriveId});
    when(() => syncCubit.completedDriveIds).thenReturn(const []);
  }

  setUp(() {
    profileCubit = MockProfileCubit();
    driveDetailCubit = MockDriveDetailCubit();
    drivesCubit = MockDrivesCubit();
    syncCubit = MockSyncBloc();
    auth = MockArDriveAuth();
    router = AppRouterDelegate();
    configService = MockConfigService();
    when(() => configService.config).thenReturn(
      AppConfig(allowedDataItemSizeForTurbo: 0, stripePublishableKey: ''),
    );

    when(() => profileCubit.state).thenReturn(
      ProfileLoggedIn(user: fakeUserJson, useTurbo: true),
    );
    when(() => auth.currentUser).thenReturn(fakeUserJson);
    when(() => driveDetailCubit.syncCurrentDrive()).thenAnswer((_) async {});
    syncing();
  });

  Future<void> pumpMenu(
    WidgetTester tester, {
    bool bottomNavigation = false,
    DriveDetailState? state,
    String? openDriveId,
    DrivesState? drivesState,
    Drive? drive,
    FolderWithContents? currentFolder,
    bool webPages = false,
  }) async {
    // No drive open, unless a test says otherwise: what the drives list
    // route provides.
    final detailState = state ?? DriveDetailLoadInProgress();
    whenListen(
      driveDetailCubit,
      const Stream<DriveDetailState>.empty(),
      initialState: detailState,
    );
    whenListen(
      drivesCubit,
      const Stream<DrivesState>.empty(),
      initialState: drivesState ??
          DrivesLoadSuccess(
            selectedDriveId: null,
            userDrives: [_drive(ownerAddress: fakeUserJson.walletAddress)],
            sharedDrives: const [],
            drivesWithAlerts: const [],
            canCreateNewDrive: true,
          ),
    );
    // A drive in view is a drive page, and the drives list is not one.
    final inDrive = state is DriveDetailLoadUnsynced ||
        state is DriveDetailLoadSuccess ||
        openDriveId != null;
    if (webPages) {
      // The page is only there with publishing on.
      when(() => configService.config).thenReturn(AppConfig(
        allowedDataItemSizeForTurbo: 0,
        stripePublishableKey: '',
        enableDriveStatePublishing: true,
      ));
    }
    router
      ..showingDrivesList = !inDrive && !webPages
      ..showingWebPages = webPages
      ..driveId = openDriveId ??
          (state is DriveDetailLoadUnsynced ? state.drive.id : null);

    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          home: RepositoryProvider<ArDriveAuth>.value(
            value: auth,
            child: MultiProvider(
              providers: [
                ListenableProvider<AppRouterDelegate>.value(value: router),
                BlocProvider<ProfileCubit>.value(value: profileCubit),
                BlocProvider<DriveDetailCubit>.value(value: driveDetailCubit),
                BlocProvider<DrivesCubit>.value(value: drivesCubit),
                BlocProvider<SyncCubit>.value(value: syncCubit),
                // Read by the drive state publishing entry, which stays hidden
                // here: its flag ships off, as it does in production.
                RepositoryProvider<ConfigService>.value(value: configService),
              ],
              child: Scaffold(
                body: Center(
                  child: NewButton(
                    drive: drive,
                    currentFolder: currentFolder,
                    driveDetailState: detailState,
                    isBottomNavigationButton: bottomNavigation,
                    child: bottomNavigation ? null : const Text('open me'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // The plus button draws its own control and opens a modal; the sidebar
    // menu wraps whatever child it is given.
    await tester.tap(
      bottomNavigation ? find.byType(ArDriveFAB) : find.text('open me'),
    );
    await tester.pumpAndSettle();
  }

  /// The same lookup `drives_list_menu_test.dart` uses: the tile picks its
  /// colours off this flag alone, so it is the flag that says whether a row is
  /// offered or drawn dead.
  ArDriveDropdownItemTile tile(WidgetTester tester, String name) =>
      tester.widget<ArDriveDropdownItemTile>(
        find.widgetWithText(ArDriveDropdownItemTile, name),
      );

  double top(WidgetTester tester, Finder finder) =>
      tester.getTopLeft(finder).dy;

  // The sidebar menu is ArDriveSubmenu. Its items were not buttons, so with
  // the browser's accessibility tree on the web gave them no role and no name.
  group('with a screen reader', () {
    testWidgets('a visitor hears "Open another drive" as a button',
        (tester) async {
      final semantics = tester.ensureSemantics();
      when(() => profileCubit.state).thenReturn(ProfilePromptAdd());
      await pumpMenu(tester);
      // The signed-out menu, which offers nothing else.
      expect(find.text('Upload folder'), findsNothing);

      expect(
        tester.getSemantics(find.bySemanticsLabel('Open another drive')),
        containsSemantics(
          label: 'Open another drive',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );

      semantics.dispose();
    });

    testWidgets('and a signed-in reader hears the upload items as buttons',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpMenu(tester);

      for (final name in ['Upload files', 'Upload folder']) {
        expect(
          tester.getSemantics(find.bySemanticsLabel(name)),
          containsSemantics(isButton: true, hasTapAction: true),
          reason: name,
        );
      }

      semantics.dispose();
    });
  });

  group('with no drive open', () {
    /// The one thing most people open this menu for.
    testWidgets('offers uploading', (tester) async {
      await pumpMenu(tester);

      expect(tile(tester, 'Upload files').isDisabled, isFalse);
      expect(tile(tester, 'Upload folder').isDisabled, isFalse);
    });

    testWidgets('offers a new drive', (tester) async {
      await pumpMenu(tester);

      expect(
        find.text('New drive'),
        findsOneWidget,
        reason: 'it was gated on the drive list having loaded, which creating '
            'a drive does not depend on',
      );
    });

    /// A wallet that cannot pay is not a reason to withhold the action. The
    /// dialog behind it says there is not enough AR and offers to top up,
    /// which is more use than a control that does nothing, and it matches the
    /// getting started cards, which open the same dialog ungated.
    testWidgets('offers a new drive even when the wallet cannot pay',
        (tester) async {
      when(() => profileCubit.state).thenReturn(
        // Zero balance, and no Turbo to fall back on.
        ProfileLoggedIn(user: fakeUserJson, useTurbo: false),
      );

      await pumpMenu(tester);

      expect(tile(tester, 'New drive').isDisabled, isFalse);
    });

    /// One action behind a submenu row is a menu that looks empty.
    testWidgets('puts attaching a drive at the top level', (tester) async {
      await pumpMenu(tester);

      expect(find.text('Attach drive'), findsOneWidget);
      expect(find.text('Advanced'), findsNothing);
    });

    testWidgets('leads with uploading, ruled off from the drive actions',
        (tester) async {
      await pumpMenu(tester);

      final upload = top(tester, find.text('Upload folder'));
      final rule = top(tester, find.byType(Divider).first);
      final newDrive = top(tester, find.text('New drive'));

      expect(upload, lessThan(rule));
      expect(rule, lessThan(newDrive));
    });
  });

  /// The mobile plus button keeps the same rules. The drive page only draws it
  /// once its drive has loaded, so these hold it in step with the sidebar
  /// rather than describe a state it reaches today.
  group('on the mobile plus button, with no drive open', () {
    testWidgets('offers the same actions', (tester) async {
      await pumpMenu(tester, bottomNavigation: true);

      expect(find.text('Upload files'), findsOneWidget);
      expect(find.text('Upload folder'), findsOneWidget);
      expect(find.text('New drive'), findsOneWidget);
      expect(find.text('Attach drive'), findsOneWidget);
      expect(find.text('Advanced'), findsNothing);
    });

    /// A rule with nothing above it drew a hairline across the top of the
    /// sheet before its first item.
    testWidgets('opens with an item rather than a rule', (tester) async {
      await pumpMenu(tester, bottomNavigation: true);

      expect(
        top(tester, find.text('Upload files')),
        lessThan(top(tester, find.byType(Divider).first)),
      );
    });
  });

  /// The menu keeps its shape whether or not the app has read the drive.
  /// "Synced" is the app's word, and a menu that grows items after a sync
  /// teaches the reader only that it is unpredictable.
  group('in a drive nothing has read yet', () {
    testWidgets('offers the folder actions too', (tester) async {
      await pumpMenu(
        tester,
        state: DriveDetailLoadUnsynced(
          drive: _drive(ownerAddress: fakeUserJson.walletAddress),
        ),
      );

      for (final action in ['New folder', 'New note', 'New file pin']) {
        expect(tile(tester, action).isDisabled, isFalse, reason: action);
      }
    });

    /// They only make sense inside a drive: on the drives list there is no
    /// folder for any of them to go into.
    testWidgets('which the drives list does not offer at all', (tester) async {
      await pumpMenu(tester);

      expect(find.text('New folder'), findsNothing);
      expect(find.text('New note'), findsNothing);
      expect(find.text('New file pin'), findsNothing);
    });

    /// Uploading there leads to its sync first, so it is offered.
    testWidgets('offers uploading into your own drive', (tester) async {
      await pumpMenu(
        tester,
        state: DriveDetailLoadUnsynced(
          drive: _drive(ownerAddress: fakeUserJson.walletAddress),
        ),
      );

      expect(tile(tester, 'Upload files').isDisabled, isFalse);
    });

    /// Syncing somebody else's drive would only arrive at the same answer.
    testWidgets("keeps somebody else's drive read-only", (tester) async {
      await pumpMenu(
        tester,
        state: DriveDetailLoadUnsynced(
          drive: _drive(ownerAddress: 'somebody-else'),
        ),
      );

      expect(tile(tester, 'Upload files').isDisabled, isTrue);
      expect(tile(tester, 'Upload folder').isDisabled, isTrue);
    });

    testWidgets('pressing New Folder starts its sync', (tester) async {
      await pumpMenu(
        tester,
        state: DriveDetailLoadUnsynced(
          drive: _drive(ownerAddress: fakeUserJson.walletAddress),
        ),
      );

      await tester.tap(find.text('New folder'));
      await tester.pumpAndSettle();

      verify(() => driveDetailCubit.syncCurrentDrive()).called(1);
    });

    /// One sync at a time and no queue, so the press says why nothing
    /// happened rather than looking ignored.
    testWidgets('while a sync reads it, says so and starts nothing',
        (tester) async {
      syncing(syncingDriveId: 'photos');
      await pumpMenu(
        tester,
        state: DriveDetailLoadUnsynced(
          drive: _drive(ownerAddress: fakeUserJson.walletAddress),
        ),
      );

      await tester.tap(find.text('New folder'));
      await tester.pump();

      expect(
        find.text('This drive is syncing. Try again once it finishes.'),
        findsOneWidget,
      );
      verifyNever(() => driveDetailCubit.syncCurrentDrive());
    });

    /// Its card already says nothing was found on chain and offers to look
    /// again. There is no folder to put anything in yet.
    testWidgets('greys everything when its sync found nothing', (tester) async {
      await pumpMenu(
        tester,
        state: DriveDetailLoadUnsynced(
          drive: _drive(ownerAddress: fakeUserJson.walletAddress),
          syncFoundNothing: true,
        ),
      );

      for (final action in [
        'Upload files',
        'Upload folder',
        'New folder',
        'New note',
        'New file pin',
      ]) {
        expect(tile(tester, action).isDisabled, isTrue, reason: action);
      }
    });

    /// Pinning a file never needed a balance, and still does not.
    testWidgets('offers New File Pin to a wallet that cannot pay',
        (tester) async {
      when(() => profileCubit.state).thenReturn(
        ProfileLoggedIn(user: fakeUserJson, useTurbo: false),
      );
      await pumpMenu(
        tester,
        state: DriveDetailLoadUnsynced(
          drive: _drive(ownerAddress: fakeUserJson.walletAddress),
        ),
      );

      expect(tile(tester, 'New folder').isDisabled, isTrue);
      expect(tile(tester, 'New file pin').isDisabled, isFalse);
    });
  });

  /// Opening a drive passes through a moment with nothing loaded, and a sync
  /// can hold a drive there for minutes. The menu keeps its shape through
  /// both.
  group('in a drive that is opening', () {
    testWidgets('keeps the folder actions, greyed for that moment',
        (tester) async {
      await pumpMenu(
        tester,
        state: DriveDetailLoadInProgress(),
        openDriveId: 'photos',
      );

      for (final action in ['New folder', 'New note', 'New file pin']) {
        expect(tile(tester, action).isDisabled, isTrue, reason: action);
      }
      expect(
        tile(tester, 'Upload files').isDisabled,
        isFalse,
        reason: 'an upload waits the second or two a drive takes to open',
      );
    });

    testWidgets('and, while a sync reads it, says so when pressed',
        (tester) async {
      syncing(syncingDriveId: 'photos');
      await pumpMenu(
        tester,
        state: DriveDetailLoadInProgress(),
        openDriveId: 'photos',
      );

      await tester.tap(find.text('New note'));
      await tester.pump();

      expect(
        find.text('This drive is syncing. Try again once it finishes.'),
        findsOneWidget,
      );
    });
  });

  /// Web pages holds no folder, and its explorer cubit stays loading with
  /// the last drive still selected underneath. That read as a drive opening:
  /// Upload queued an upload for an explorer that never came, and did
  /// nothing. Upload now asks where; the folder actions, with no folder to
  /// go into, are left out as on the drives list.
  group('on Web pages', () {
    testWidgets('offers uploading, and no folder actions', (tester) async {
      await pumpMenu(
        tester,
        webPages: true,
        openDriveId: 'photos',
        state: DriveDetailLoadInProgress(),
      );

      expect(tile(tester, 'Upload files').isDisabled, isFalse);
      expect(tile(tester, 'Upload folder').isDisabled, isFalse);
      for (final action in ['New folder', 'New note', 'New file pin']) {
        expect(find.text(action), findsNothing, reason: action);
      }
    });
  });

  /// There is nowhere yet for Upload to lead.
  testWidgets('Upload is greyed until the drive list is known', (tester) async {
    await pumpMenu(tester, drivesState: DrivesLoadInProgress());

    expect(tile(tester, 'Upload files').isDisabled, isTrue);
    expect(tile(tester, 'Upload folder').isDisabled, isTrue);
  });

  Finder readingTooltip() => find.byWidgetPredicate(
        (w) => w is ArDriveTooltip && w.message == 'Reading your drives',
      );

  testWidgets('and says why while it is greyed', (tester) async {
    await pumpMenu(tester, drivesState: DrivesLoadInProgress());

    expect(readingTooltip(), findsNWidgets(2));
  });

  testWidgets('and offers no such tooltip once Upload works', (tester) async {
    await pumpMenu(tester);

    expect(readingTooltip(), findsNothing);
  });

  /// It sat at the top of the plus menu and inside Advanced, so a public
  /// drive listed it twice. Advanced is where the sidebar menu keeps it.
  testWidgets('the plus menu lists Import from manifest only under Advanced',
      (tester) async {
    final website = _drive(
      ownerAddress: fakeUserJson.walletAddress,
      privacy: 'public',
    );
    final entry = _FolderEntry();
    when(() => entry.id).thenReturn('root-photos');
    final folder = _Folder();
    when(() => folder.folder).thenReturn(entry);
    final loaded = _Loaded();
    when(() => loaded.currentDrive).thenReturn(website);
    when(() => loaded.hasWritePermissions).thenReturn(true);
    when(() => loaded.driveIsEmpty).thenReturn(false);
    when(() => loaded.folderInView).thenReturn(folder);

    await pumpMenu(
      tester,
      bottomNavigation: true,
      state: loaded,
      drive: website,
      currentFolder: folder,
    );

    expect(find.text('Advanced'), findsOneWidget);
    expect(find.text('Import from manifest'), findsNothing);
  });
}

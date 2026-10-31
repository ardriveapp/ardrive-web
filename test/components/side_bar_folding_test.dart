import 'dart:async';

import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/presentation/names/arns_names_cubit.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/components/nav_sections.dart';
import 'package:ardrive/components/side_bar.dart';
import 'package:ardrive/drives_list/domain/drive_scope.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive/web_pages/domain/web_page.dart';
import 'package:ardrive/web_pages/presentation/web_pages_cubit.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../test_utils/fake_user.dart';
import '../test_utils/mocks.dart';

class _MockGlobalHideBloc extends MockBloc<GlobalHideEvent, GlobalHideState>
    implements GlobalHideBloc {}

class _MockConfigService extends Mock implements ConfigService {}

class _MockNamesCubit extends MockCubit<ArNSNamesState>
    implements ArNSNamesCubit {}

class _MockWebPagesCubit extends MockCubit<WebPagesState>
    implements WebPagesCubit {}

class _MockPreferences extends Mock implements UserPreferencesRepository {}

UserPreferences _prefs(Set<String> folded) => UserPreferences(
      currentTheme: ArDriveThemes.light,
      lastSelectedDriveId: null,
      foldedNavSections: folded,
    );

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

/// Folding a heading in the sidebar is the reader arranging their nav, and
/// it stays arranged wherever they go.
///
/// Each page the router shows draws a sidebar of its own, so a fold kept in
/// the sidebar was lost on every move: opening Web pages opened Public and
/// Private again.
void main() {
  late MockDrivesCubit drivesCubit;
  late MockProfileCubit profileCubit;
  late MockDriveDetailCubit driveDetailCubit;
  late MockSyncBloc syncCubit;
  late _MockGlobalHideBloc hideBloc;
  late _MockConfigService config;
  late _MockNamesCubit names;
  late _MockWebPagesCubit webPages;
  late AppRouterDelegate router;
  late _MockPreferences preferences;
  late StreamController<UserPreferences> preferencesChanged;

  setUpAll(() => registerFallbackValue(<String>{}));

  setUp(() {
    preferences = _MockPreferences();
    preferencesChanged = StreamController.broadcast(sync: true);
    addTearDown(preferencesChanged.close);
    when(() => preferences.currentPreferences).thenReturn(_prefs(const {}));
    when(() => preferences.watch())
        .thenAnswer((_) => preferencesChanged.stream);
    when(() => preferences.saveFoldedNavSections(any()))
        .thenAnswer((_) async {});

    drivesCubit = MockDrivesCubit();
    profileCubit = MockProfileCubit();
    driveDetailCubit = MockDriveDetailCubit();
    syncCubit = MockSyncBloc();
    whenListen(syncCubit, const Stream<SyncState>.empty(),
        initialState: SyncIdle());
    when(() => syncCubit.syncingDriveId).thenReturn(null);
    when(() => syncCubit.completedDriveIds).thenReturn(const []);
    when(() => syncCubit.syncingDriveIds).thenReturn(null);
    hideBloc = _MockGlobalHideBloc();
    config = _MockConfigService();
    names = _MockNamesCubit();
    webPages = _MockWebPagesCubit();
    router = AppRouterDelegate();

    when(() => config.config).thenReturn(AppConfig(
      stripePublishableKey: '',
      allowedDataItemSizeForTurbo: 100,
      enableArNS: true,
      enableDriveStatePublishing: true,
    ));
    whenListen(profileCubit, const Stream<ProfileState>.empty(),
        initialState: ProfileLoggedIn(user: fakeUserJson, useTurbo: true));
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
    whenListen(
      webPages,
      const Stream<WebPagesState>.empty(),
      initialState: WebPagesState(loaded: true, pages: [
        WebPage(
          kind: WebPageKind.deployment,
          id: 'page-1',
          title: 'Homepage',
          driveId: 'website',
          driveName: 'website',
          folderName: null,
          openFolderId: 'website-root',
          dataTxId: 'tx-1',
          updatedAt: DateTime(2026),
        ),
      ]),
    );
    whenListen(
      names,
      const Stream<ArNSNamesState>.empty(),
      initialState: const ArNSNamesState(
        status: ArNSNamesStatus.loaded,
        address: 'sol',
        names: [
          ArNSManagedName(
            name: 'maya',
            processId: 'ant-maya',
            role: ArNSRole.owner,
            type: ArNSNameType.permabuy,
            endTimestamp: null,
            undernameLimit: 10,
            records: [],
          ),
        ],
      ),
    );
  });

  /// The app's shape: the folding above the router, and a sidebar built
  /// afresh for each page, the way each shell the router builds has its own.
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MultiProvider(
            providers: [
              RepositoryProvider<ConfigService>.value(value: config),
              ChangeNotifierProvider<AppRouterDelegate>.value(value: router),
              BlocProvider<DrivesCubit>.value(value: drivesCubit),
              BlocProvider<ProfileCubit>.value(value: profileCubit),
              BlocProvider<DriveDetailCubit>.value(value: driveDetailCubit),
              BlocProvider<SyncCubit>.value(value: syncCubit),
              BlocProvider<GlobalHideBloc>.value(value: hideBloc),
              BlocProvider<ArNSNamesCubit>.value(value: names),
              BlocProvider<WebPagesCubit>.value(value: webPages),
              BlocProvider(
                create: (_) => NavSectionsCubit(preferences: preferences),
              ),
            ],
            child: ListenableBuilder(
              listenable: router,
              builder: (context, _) => Scaffold(
                // The drives list's nav is the scope rail, a different nav,
                // and needs that page's cubit: this stands in for the page.
                body: router.showingDrivesList
                    ? const Text('drives list')
                    : AppSideBar(
                        key: ValueKey(
                          router.showingWebPages
                              ? 'webPages'
                              : router.showingNames
                                  ? 'names'
                                  : 'explorer',
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> fold(WidgetTester tester, String heading) async {
    await tester.tap(find.byKey(ValueKey('nav-toggle-$heading')));
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> open(WidgetTester tester, String heading) async {
    await tester.tap(find.text(heading));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> openDrive(WidgetTester tester) async {
    router.openDriveFromList('photos');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// What each heading has under it, so a test can tell folded from open.
  const under = {
    'Public drives': 'website',
    'Private drives': 'photos',
    'Shared with me': 'shared',
    'Web pages': 'Homepage',
    'Names': 'maya',
  };

  void expectFolded(Set<String> folded) {
    for (final MapEntry(key: heading, value: row) in under.entries) {
      expect(
        find.text(row),
        folded.contains(heading) ? findsNothing : findsOneWidget,
        reason: folded.contains(heading)
            ? '$heading opened again'
            : '$heading was folded',
      );
    }
  }

  group("a drives heading's words open its page and fold nothing", () {
    for (final (heading, scope) in [
      ('Public drives', DriveScope.public),
      ('Private drives', DriveScope.private),
      ('Shared with me', DriveScope.sharedWithMe),
    ]) {
      testWidgets(heading, (tester) async {
        await pumpApp(tester);

        await open(tester, heading);
        expect(router.showingDrivesList, isTrue);
        expect(router.drivesListScope, scope);

        await openDrive(tester);
        expectFolded(const {});
        verifyNever(() => preferences.saveFoldedNavSections(any()));
      });
    }

  });

  // Phil: opening Web pages leaves only Web pages open; Names likewise.
  group("Web pages' and Names' words open the page and fold everything else",
      () {
    testWidgets('Web pages', (tester) async {
      await pumpApp(tester);

      await open(tester, 'Web pages');

      expect(router.showingWebPages, isTrue);
      expectFolded(under.keys.toSet()..remove('Web pages'));
    });

    testWidgets('Names', (tester) async {
      await pumpApp(tester);

      await open(tester, 'Names');

      expect(router.showingNames, isTrue);
      expectFolded(under.keys.toSet()..remove('Names'));
    });
  });

  testWidgets("a heading's chevron folds it and opens nothing", (tester) async {
    await pumpApp(tester);

    for (final heading in under.keys) {
      await fold(tester, heading);
    }

    expectFolded(under.keys.toSet());
    expect(router.showingDrivesList, isFalse);
    expect(router.showingWebPages, isFalse);
    expect(router.showingNames, isFalse);
  });

  testWidgets('a fold stays made in a drive and on the page opened after',
      (tester) async {
    await pumpApp(tester);

    await open(tester, 'Names');
    final names = under.keys.toSet()..remove('Names');
    expectFolded(names);

    await openDrive(tester);
    expect(router.showingNames, isFalse);
    expectFolded(names);

    // Unfolded by hand, and still so in the next drive.
    await fold(tester, 'Public drives');
    await openDrive(tester);
    expectFolded(names..remove('Public drives'));
  });

  testWidgets('each fold is saved with the preferences', (tester) async {
    await pumpApp(tester);

    await fold(tester, 'Private drives');
    verify(() => preferences.saveFoldedNavSections({'privateDrives'}))
        .called(1);

    await fold(tester, 'Web pages');
    verify(
      () => preferences.saveFoldedNavSections({'privateDrives', 'webPages'}),
    ).called(1);
  });

  testWidgets('a sidebar built from saved preferences is folded as saved',
      (tester) async {
    when(() => preferences.currentPreferences)
        .thenReturn(_prefs(const {'publicDrives', 'names', 'unknownHeading'}));

    await pumpApp(tester);

    expectFolded(const {'Public drives', 'Names'});
  });

  testWidgets(
      'preferences read after start, or cleared on logout, are followed',
      (tester) async {
    await pumpApp(tester);
    expectFolded(const {});

    preferencesChanged.add(_prefs(const {'sharedDrives', 'webPages'}));
    await tester.pump(const Duration(milliseconds: 200));
    expectFolded(const {'Shared with me', 'Web pages'});

    preferencesChanged.add(_prefs(const {}));
    await tester.pump(const Duration(milliseconds: 200));
    expectFolded(const {});
  });
}

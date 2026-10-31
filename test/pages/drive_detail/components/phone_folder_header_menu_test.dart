import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/components/private_drive_marks.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
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

import '../../../test_utils/utils.dart';

class _MockSyncCubit extends MockCubit<SyncState> implements SyncCubit {}

class _MockGlobalHideBloc extends MockBloc<GlobalHideEvent, GlobalHideState>
    implements GlobalHideBloc {}

/// #29: inside a folder on a phone, the header names the folder, but its
/// menu was the drive's, so Rename and Hide acted on the whole drive.
void main() {
  late MockProfileCubit profileCubit;
  late MockDriveDetailCubit detailCubit;
  late _MockSyncCubit syncCubit;
  late MockArDriveAuth auth;
  late _MockGlobalHideBloc hideBloc;

  final drive = Drive(
    id: 'drive',
    rootFolderId: 'root',
    name: 'Photos',
    ownerAddress: getTestUser().walletAddress,
    dateCreated: DateTime(2026, 1, 1),
    lastUpdated: DateTime(2026, 1, 1),
    privacy: 'public',
    isHidden: false,
  );

  FolderEntry folder(String id, {String? parent}) => FolderEntry(
        id: id,
        driveId: 'drive',
        name: id == 'root' ? 'Photos' : 'Trips',
        parentFolderId: parent,
        path: '',
        dateCreated: DateTime(2026, 1, 1),
        lastUpdated: DateTime(2026, 1, 1),
        isGhost: false,
        isHidden: false,
      );

  DriveDetailLoadSuccess stateIn(FolderEntry shown) => DriveDetailLoadSuccess(
        currentDrive: drive,
        hasWritePermissions: true,
        folderInView: FolderWithContents(
          folder: shown,
          subfolders: const [],
          files: const [],
        ),
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
      );

  setUp(() {
    profileCubit = MockProfileCubit();
    detailCubit = MockDriveDetailCubit();
    syncCubit = _MockSyncCubit();
    auth = MockArDriveAuth();
    hideBloc = _MockGlobalHideBloc();
    whenListen(hideBloc, const Stream<GlobalHideState>.empty(),
        initialState: const HiddingItems(userHasHiddenDrive: false));
    when(() => auth.currentUser).thenReturn(getTestUser());
    whenListen(
      profileCubit,
      const Stream<ProfileState>.empty(),
      initialState: ProfileLoggedIn(user: getTestUser(), useTurbo: false),
    );
    whenListen(
      syncCubit,
      const Stream<SyncState>.empty(),
      initialState: SyncIdle(),
    );
  });

  Future<void> pumpIn(WidgetTester tester, FolderEntry shown) async {
    whenListen(
      detailCubit,
      const Stream<DriveDetailState>.empty(),
      initialState: stateIn(shown),
    );
    await tester.binding.setSurfaceSize(const Size(360, 800));
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
          home: Provider<ArDriveAuth>.value(
            value: auth,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ProfileCubit>.value(value: profileCubit),
                BlocProvider<DriveDetailCubit>.value(value: detailCubit),
                BlocProvider<SyncCubit>.value(value: syncCubit),
                BlocProvider<GlobalHideBloc>.value(value: hideBloc),
              ],
              child: Portal(
                child: Scaffold(
                  body: MobileFolderNavigation(
                    driveName: 'Photos',
                    isShowingHiddenFiles: false,
                    isPrivate: false,
                    path: [
                      if (shown.id != 'root')
                        BreadCrumbRowInfo(text: 'Trips', targetId: 'trips'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byType(HoverWidget));
    await tester.pumpAndSettle();
  }

  testWidgets('inside a folder, the menu acts on the folder', (tester) async {
    await pumpIn(tester, folder('trips', parent: 'root'));
    await openMenu(tester);

    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Move'), findsOneWidget);
    expect(find.text('Rename drive'), findsNothing);
    expect(find.text('Share drive'), findsNothing);
    expect(find.text('Sync this drive'), findsNothing);
    // The folder is already open, so Open would go nowhere.
    expect(find.text('Open'), findsNothing);
  });

  testWidgets('at the drive root, the menu is still the drive\'s',
      (tester) async {
    await pumpIn(tester, folder('root'));
    await openMenu(tester);

    expect(find.text('Rename drive'), findsOneWidget);
    expect(find.text('Share drive'), findsOneWidget);
    expect(find.text('Move'), findsNothing);
  });

  // Phil's header nits: the header's menu sat about 24 px left of the rows',
  // the private mark was the drive-with-a-lock glyph, and the name was tiny.
  group('the header', () {
    Future<void> pumpWithRow(WidgetTester tester,
        {bool private = false}) async {
      whenListen(
        detailCubit,
        const Stream<DriveDetailState>.empty(),
        initialState: stateIn(folder('root')),
      );
      when(() => detailCubit.selectedItem).thenReturn(null);
      await tester.binding.setSurfaceSize(const Size(390, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final file = FileDataTableItem(
        driveId: 'drive',
        lastUpdated: DateTime(2026, 1, 1),
        name: 'notes.md',
        size: 10,
        dateCreated: DateTime(2026, 1, 1),
        contentType: 'text/markdown',
        index: 0,
        isOwner: true,
        fileId: 'file',
        parentFolderId: 'root',
        dataTxId: 'tx',
        lastModifiedDate: DateTime(2026, 1, 1),
        metadataTx: null,
        dataTx: null,
        pinnedDataOwnerAddress: null,
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
            home: Provider<ArDriveAuth>.value(
              value: auth,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<ProfileCubit>.value(value: profileCubit),
                  BlocProvider<DriveDetailCubit>.value(value: detailCubit),
                  BlocProvider<SyncCubit>.value(value: syncCubit),
                  BlocProvider<GlobalHideBloc>.value(value: hideBloc),
                ],
                child: Portal(
                  child: Scaffold(
                    body: Column(
                      children: [
                        MobileFolderNavigation(
                          driveName: 'Photos',
                          isShowingHiddenFiles: false,
                          isPrivate: private,
                          path: const [],
                        ),
                        Expanded(
                          child: ArDriveItemList(
                            items: [file],
                            drive: drive,
                            selectedItem: null,
                          ),
                        ),
                      ],
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

    testWidgets('its menu lines up with the rows\' menus', (tester) async {
      await pumpWithRow(tester);

      final kebabs = find.byIcon(ArDriveIcons.kebabMenu().icon);
      expect(kebabs, findsNWidgets(2));
      expect(
        tester.getRect(kebabs.at(0)).right,
        tester.getRect(kebabs.at(1)).right,
      );
    });

    testWidgets('a private drive gets the sidebar\'s plain lock',
        (tester) async {
      await pumpWithRow(tester, private: true);

      final lock =
          tester.widget<PrivateDriveLock>(find.byType(PrivateDriveLock));
      expect(lock.plain, isTrue);
      expect(find.byIcon(ArDriveIcons.lock().icon), findsOneWidget);
      expect(find.byIcon(ArDriveIcons.privateDrive().icon), findsNothing);
    });

    testWidgets('the name is set as the page title is', (tester) async {
      await pumpWithRow(tester);

      final title = tester.widget<Text>(find.text('Photos'));
      final context = tester.element(find.text('Photos'));
      final expected = ArDriveTypographyNew.of(context).heading3(
        color: ArDriveTheme.of(context).themeData.colorTokens.textHigh,
        fontWeight: ArFontWeight.bold,
      );
      expect(title.style?.fontSize, expected.fontSize);
      expect(title.style?.fontWeight, expected.fontWeight);
    });
  });

  // B4: the top bar's eye is gone. A phone has no columns menu, so the
  // folder header's menu carries Show hidden items, while something is hidden.
  group('Show hidden items on a phone', () {
    testWidgets('is offered while something is hidden, and shows it',
        (tester) async {
      hideBloc = _MockGlobalHideBloc();
      whenListen(hideBloc, const Stream<GlobalHideState>.empty(),
          initialState: const HiddingItems(userHasHiddenDrive: true));
      await pumpIn(tester, folder('trips', parent: 'root'));
      await openMenu(tester);

      await tester.tap(find.text('Show hidden items'));
      await tester.pumpAndSettle();

      verify(() => hideBloc.add(const ShowItems(userHasHiddenItems: true)))
          .called(1);
    });

    testWidgets('and hides them again when they show', (tester) async {
      hideBloc = _MockGlobalHideBloc();
      whenListen(hideBloc, const Stream<GlobalHideState>.empty(),
          initialState: const ShowingHiddenItems(userHasHiddenDrive: true));
      await pumpIn(tester, folder('root'));
      await openMenu(tester);

      await tester.tap(find.text('Show hidden items'));
      await tester.pumpAndSettle();

      verify(() => hideBloc.add(const HideItems(userHasHiddenItems: true)))
          .called(1);
    });

    testWidgets('is not offered with nothing hidden', (tester) async {
      await pumpIn(tester, folder('trips', parent: 'root'));
      await openMenu(tester);

      expect(find.text('Show hidden items'), findsNothing);
    });
  });
}

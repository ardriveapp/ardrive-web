import 'dart:async';

import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/drive_detail_syncing_card.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../test_utils/mocks.dart';

class _MockDrivesCubit extends MockCubit<DrivesState> implements DrivesCubit {}

class _MockTurboUploadService extends Mock implements TurboUploadService {}

class _MockConfigService extends Mock implements ConfigService {}

class _MockAppConfig extends Mock implements AppConfig {}

Drive _drive(String id, {String privacy = 'public'}) => Drive(
      id: id,
      rootFolderId: 'root',
      ownerAddress: 'owner',
      name: 'My Drive',
      privacy: privacy,
      dateCreated: DateTime(2026, 3, 1),
      lastUpdated: DateTime(2026, 3, 1),
      isHidden: false,
    );

/// What an empty drive opens on. A new user's only drive opens on one place
/// to drop or choose files; later drives on the action cards.
void main() {
  late _MockDrivesCubit drivesCubit;
  late TurboUploadService turboUploadService;
  late _MockConfigService configService;
  late MockSyncBloc syncCubit;
  late StreamController<SyncState> syncStates;
  late StreamController<SyncProgress> progress;

  void withDrives(List<Drive> drives) => whenListen(
        drivesCubit,
        const Stream<DrivesState>.empty(),
        initialState: DrivesLoadSuccess(
          selectedDriveId: 'drive-a',
          userDrives: drives,
          sharedDrives: const [],
          drivesWithAlerts: const [],
          canCreateNewDrive: true,
        ),
      );

  setUp(() {
    drivesCubit = _MockDrivesCubit();
    final turbo = _MockTurboUploadService();
    turboUploadService = turbo;

    // What Turbo reports today: 105 KiB.
    when(() => turbo.maxFreeItemSizeBytes).thenReturn(107520);
    when(() => turbo.reportedMaxFreeItemSizeBytes).thenReturn(107520);

    final appConfig = _MockAppConfig();
    when(() => appConfig.allowedDataItemSizeForTurbo).thenReturn(100000);
    configService = _MockConfigService();
    when(() => configService.config).thenReturn(appConfig);

    // Exactly one drive is what makes this the new-user page rather than the
    // existing-user one.
    withDrives([_drive('drive-a')]);

    syncCubit = MockSyncBloc();
    syncStates = StreamController<SyncState>.broadcast();
    progress = StreamController<SyncProgress>.broadcast();
    whenListen(syncCubit, syncStates.stream, initialState: SyncIdle());
    when(() => syncCubit.syncingDriveId).thenReturn('drive-a');
    when(() => syncCubit.syncingDriveIds).thenReturn(null);
    when(() => syncCubit.syncStartTime).thenReturn(DateTime(2026, 4, 1));
    when(() => syncCubit.syncProgressController).thenReturn(progress);
    when(() => syncCubit.syncProgress).thenReturn(SyncProgress.initial());
  });

  tearDown(() async {
    await syncStates.close();
    await progress.close();
  });

  Future<void> pumpAt(
    WidgetTester tester,
    Size size, {
    bool dark = false,
    double textScale = 1,
    bool canAddFiles = true,
    bool isRootFolder = true,
    bool desktop = false,
    bool contentsStillArriving = false,
    bool isPrivate = false,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // The page picks its phone or desktop layout from MediaQuery, which
    // `setSurfaceSize` alone leaves at the default 800x600 - a phone.
    if (desktop) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    await tester.pumpWidget(
      ArDriveTheme(
        themeData: dark
            ? ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode())
            : lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: MultiRepositoryProvider(
              providers: [
                RepositoryProvider<TurboUploadService>.value(
                    value: turboUploadService),
                RepositoryProvider<ConfigService>.value(value: configService),
              ],
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<DrivesCubit>.value(value: drivesCubit),
                  BlocProvider<SyncCubit>.value(value: syncCubit),
                ],
                child: DriveDetailFolderEmptyCard(
                  driveId: 'drive-a',
                  parentFolderId: 'root',
                  promptToAddFiles: canAddFiles,
                  folderName: 'My Drive',
                  isRootFolder: isRootFolder,
                  isPrivate: isPrivate,
                  contentsStillArriving: contentsStillArriving,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Leaves the tree before the test ends: the syncing panel's elapsed
  /// counter owns a periodic timer for as long as it is mounted.
  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  List<(String, ButtonVariant)> buttons(WidgetTester tester) => tester
      .widgetList<ArDriveButtonNew>(find.byType(ArDriveButtonNew))
      .map((b) => (b.text, b.variant))
      .toList();

  group("a new user's first drive", () {
    testWidgets('opens on a place to drop files, on a computer',
        (tester) async {
      await pumpAt(tester, const Size(1280, 800), desktop: true);

      expect(find.byKey(const Key('firstDriveDropArea')), findsOneWidget);
      expect(
          find.text('Drop files here to keep them for good'), findsOneWidget);
      expect(
        find.text('Or choose files from your computer. Anyone can see them.'),
        findsOneWidget,
      );
      expect(buttons(tester), [
        ('New folder', ButtonVariant.secondary),
        ('Upload files', ButtonVariant.primary),
      ]);
      expect(find.textContaining('Your drive is ready'), findsNothing);
      expect(find.byType(ArDriveImage), findsNothing, reason: 'no confetti');
    });

    testWidgets('says only its owner sees a private drive', (tester) async {
      withDrives([_drive('drive-a', privacy: 'private')]);

      await pumpAt(tester, const Size(1280, 800),
          desktop: true, isPrivate: true);

      expect(
        find.text('Or choose files from your computer. Only you can see them.'),
        findsOneWidget,
      );
    });

    testWidgets('asks a phone to choose files, not drop them', (tester) async {
      await pumpAt(tester, const Size(375, 667), isPrivate: true);

      expect(find.text('Keep your files for good'), findsOneWidget);
      expect(
        find.text('Choose photos or files to upload. Only you can see them.'),
        findsOneWidget,
      );
      expect(find.textContaining('Drop files'), findsNothing);
      expect(tester.takeException(), isNull);
      for (final label in ['Upload files', 'New folder']) {
        final rect =
            tester.getRect(find.widgetWithText(ArDriveButtonNew, label));
        expect(rect.bottom, lessThanOrEqualTo(667),
            reason: '"$label" is off the bottom of the screen');
      }
    });

    testWidgets('fits in dark mode too', (tester) async {
      await pumpAt(tester, const Size(375, 667), dark: true);

      expect(tester.takeException(), isNull);
      expect(find.text('Keep your files for good'), findsOneWidget);
    });

    testWidgets('scrolls rather than overflows at large text', (tester) async {
      await pumpAt(tester, const Size(375, 667), textScale: 1.6);

      expect(tester.takeException(), isNull);
      for (final label in ['Upload files', 'New folder']) {
        await tester.scrollUntilVisible(
          find.widgetWithText(ArDriveButtonNew, label),
          100,
        );
        expect(find.widgetWithText(ArDriveButtonNew, label), findsOneWidget);
      }
    });

    testWidgets('notes that small files upload free, until dismissed',
        (tester) async {
      await pumpAt(tester, const Size(1280, 800), desktop: true);

      const note =
          'Small files upload free while your free upload allowance lasts.';
      expect(find.text(note), findsOneWidget);

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.text(note), findsNothing);
    });

    testWidgets('makes no free promise when Turbo uploads are off',
        (tester) async {
      turboUploadService = DontUseUploadService();

      await pumpAt(tester, const Size(1280, 800), desktop: true);

      expect(find.textContaining('upload free'), findsNothing);
    });

    testWidgets('makes no free promise when Turbo has not answered',
        (tester) async {
      when(() => turboUploadService.reportedMaxFreeItemSizeBytes)
          .thenReturn(null);

      await pumpAt(tester, const Size(1280, 800), desktop: true);

      expect(find.textContaining('upload free'), findsNothing);
    });

    testWidgets('makes no free promise when nothing is free', (tester) async {
      when(() => turboUploadService.reportedMaxFreeItemSizeBytes).thenReturn(0);

      await pumpAt(tester, const Size(1280, 800), desktop: true);

      expect(find.textContaining('upload free'), findsNothing);
    });
  });

  /// The page used to say "collectively under 100KB", which is neither check
  /// the uploader makes: each file must be under the limit Turbo reports, and
  /// the upload must fit the wallet's free allowance.
  group('a later drive states the free upload rule the uploader applies', () {
    // At full scale the test font overflows this page's 221px action cards,
    // so these render smaller: they are about the copy above them.
    Future<void> pumpLater(WidgetTester tester) async {
      withDrives([_drive('drive-a'), _drive('drive-b')]);
      await pumpAt(tester, const Size(375, 667), textScale: 0.5);
    }

    testWidgets('with the limit Turbo reports', (tester) async {
      await pumpLater(tester);

      expect(find.textContaining('Your drive is ready'), findsNothing);
      expect(
        find.textContaining(
            'Files up to 105 KiB each upload free, while your free allowance '
            'lasts. For larger files, you can pay with credits.'),
        findsOneWidget,
      );
      for (final gone in ['100KB', 'blazingly', 'unlimited', 'FREE']) {
        expect(find.textContaining(gone), findsNothing, reason: gone);
      }
    });

    testWidgets('with a different limit when Turbo reports one',
        (tester) async {
      when(() => turboUploadService.maxFreeItemSizeBytes).thenReturn(204800);

      await pumpLater(tester);

      expect(find.textContaining('Files up to 200 KiB each'), findsOneWidget);
    });

    /// The service provided when config turns Turbo uploads off throws for
    /// its limit, and the page must still draw.
    testWidgets('with the configured limit when Turbo uploads are off',
        (tester) async {
      turboUploadService = DontUseUploadService();

      await pumpLater(tester);

      expect(find.textContaining('Files up to 97.66 KiB each'), findsOneWidget);
    });
  });

  /// Someone who opened a link to another person's drive. The owner's page
  /// welcomes them to a drive they just made and offers uploads they cannot
  /// make, so they get one true sentence instead.
  group('in a drive the reader cannot add to', () {
    for (final isRootFolder in [true, false]) {
      testWidgets(
          'says the folder is empty and offers nothing '
          '(${isRootFolder ? 'root' : 'subfolder'})', (tester) async {
        await pumpAt(
          tester,
          const Size(1280, 800),
          canAddFiles: false,
          isRootFolder: isRootFolder,
        );

        expect(find.text('This folder is empty.'), findsOneWidget);
        expect(find.byType(ArDriveButtonNew), findsNothing);
        for (final ownerCopy in [
          "You're on chain!",
          'Your brand new drive!',
          'Ready to organize your files?',
          'upload free',
        ]) {
          expect(find.textContaining(ownerCopy), findsNothing,
              reason: ownerCopy);
        }
      });
    }

    testWidgets('says the drive is still loading while a sync reads it',
        (tester) async {
      whenListen(syncCubit, const Stream<SyncState>.empty(),
          initialState: SyncInProgress());
      when(() => syncCubit.syncingDriveId).thenReturn('drive-a');

      await pumpAt(tester, const Size(1280, 800), canAddFiles: false);

      expect(
        find.text('This drive is still loading. Its files will appear here.'),
        findsOneWidget,
      );
      expect(find.text('This folder is empty.'), findsNothing);
    });

    testWidgets('says it is empty while a sync reads a different drive',
        (tester) async {
      whenListen(syncCubit, const Stream<SyncState>.empty(),
          initialState: SyncInProgress());
      when(() => syncCubit.syncingDriveId).thenReturn('drive-b');

      await pumpAt(tester, const Size(1280, 800), canAddFiles: false);

      expect(find.text('This folder is empty.'), findsOneWidget);
    });
  });

  /// Sync saves a drive's history oldest first, so on a first sync a folder
  /// lands before anything inside it. A full drive used to flash "Your brand
  /// new drive!" in that gap. Whether the gap is open is the cubit's call
  /// (see its tests); this is what the card does with it.
  group('while the contents are still arriving', () {
    Future<void> pumpArriving(WidgetTester tester) async {
      whenListen(syncCubit, syncStates.stream,
          initialState: SyncInProgress(trigger: SyncTrigger.userInitiated));
      await pumpAt(tester, const Size(1280, 800), contentsStillArriving: true);
    }

    testWidgets('says the sync is running rather than that the drive is new',
        (tester) async {
      await pumpArriving(tester);

      expect(find.byType(DriveDetailSyncingCard), findsOneWidget);
      expect(find.textContaining('Your drive is ready'), findsNothing);
      expect(find.textContaining('Upload'), findsNothing);

      await unmount(tester);
    });

    testWidgets('names the folder that is waiting', (tester) async {
      await pumpArriving(tester);

      expect(find.text('My Drive will open when the sync finishes'),
          findsOneWidget);

      await unmount(tester);
    });
  });

  group('an empty folder inside a drive', () {
    testWidgets('says the folder is empty, not that the drive is new',
        (tester) async {
      // Small text, as for the later-drive test above: the test font
      // overflows these cards' 221px content box at full size.
      await pumpAt(tester, const Size(1280, 800),
          isRootFolder: false, textScale: 0.5, desktop: true);

      expect(find.byType(ArDriveEmptyState), findsOneWidget);
      expect(find.text('This folder is empty'), findsOneWidget);
      // The two ways to fill it, the upload as the main one.
      final buttons =
          tester.widgetList<ArDriveButtonNew>(find.byType(ArDriveButtonNew));
      expect(buttons.map((b) => (b.text, b.variant)), [
        ('Upload folder', ButtonVariant.secondary),
        ('Upload files', ButtonVariant.primary),
      ]);
      expect(find.textContaining('new drive'), findsNothing);
      expect(find.textContaining('Your drive is ready'), findsNothing);
    });

    testWidgets('has no confetti', (tester) async {
      // Small text, as for the later-drive test above: the test font
      // overflows these cards' 221px content box at full size.
      await pumpAt(tester, const Size(1280, 800),
          isRootFolder: false, textScale: 0.5, desktop: true);

      expect(find.byType(ArDriveImage), findsNothing);
    });
  });

  /// The four cards on an empty drive used to place their titles up to 11px
  /// apart, and their buttons up to 7px, because each spread its spare space
  /// evenly around a description of a different length.
  testWidgets('the action cards line up across the row', (tester) async {
    withDrives([_drive('drive-a'), _drive('drive-b')]);

    // Wide enough for all four cards, at a text size that fits their 221px
    // content box in the test font.
    await pumpAt(tester, const Size(1600, 1000), textScale: 0.5, desktop: true);

    final titles = [
      'Upload files',
      'Upload a folder',
      'Create a folder',
      'Create a pin',
    ];
    for (final title in titles) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(tester.takeException(), isNull);

    final titleTops =
        titles.map((t) => tester.getTopLeft(find.text(t)).dy).toSet();
    expect(titleTops, hasLength(1), reason: 'titles at $titleTops');

    final buttonTops = tester
        .widgetList<ArDriveButtonNew>(find.byType(ArDriveButtonNew))
        .map((b) => tester.getTopLeft(find.byWidget(b)).dy)
        .toSet();
    expect(buttonTops, hasLength(1), reason: 'buttons at $buttonTops');
  });
}

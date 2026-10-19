import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDrivesCubit extends MockCubit<DrivesState> implements DrivesCubit {}

class _MockTurboUploadService extends Mock implements TurboUploadService {}

class _MockConfigService extends Mock implements ConfigService {}

class _MockAppConfig extends Mock implements AppConfig {}

Drive _drive(String id) => Drive(
      id: id,
      rootFolderId: 'root',
      ownerAddress: 'owner',
      name: 'My Drive',
      privacy: 'public',
      dateCreated: DateTime(2026, 3, 1),
      lastUpdated: DateTime(2026, 3, 1),
      isHidden: false,
    );

/// The page a brand new drive opens on: "Your drive is ready".
///
/// It has one job - say well done, then offer the two things worth doing next -
/// and on a phone it was doing that job below the fold, because both offers
/// were 283px squares stacked under a heading and a paragraph.
void main() {
  late _MockDrivesCubit drivesCubit;
  late TurboUploadService turboUploadService;
  late _MockConfigService configService;

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

    final appConfig = _MockAppConfig();
    when(() => appConfig.allowedDataItemSizeForTurbo).thenReturn(100000);
    configService = _MockConfigService();
    when(() => configService.config).thenReturn(appConfig);

    // Exactly one drive is what makes this the new-user page rather than the
    // existing-user one.
    withDrives([_drive('drive-a')]);
  });

  Future<void> pumpAt(
    WidgetTester tester,
    Size size, {
    bool dark = false,
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
              child: BlocProvider<DrivesCubit>.value(
                value: drivesCubit,
                child: const DriveDetailFolderEmptyCard(
                  driveId: 'drive-a',
                  parentFolderId: 'root',
                  isRootFolder: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The measurement that matters, taken rather than assumed: a scroll view
  /// whose content is shorter than its viewport has nowhere to scroll to.
  double scrollableExtent(WidgetTester tester) {
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;

    return position.maxScrollExtent;
  }

  testWidgets('fits on a phone without scrolling', (tester) async {
    // A small-but-real phone viewport: iPhone SE is 375x667.
    await pumpAt(tester, const Size(375, 667));

    expect(find.textContaining('Your drive is ready'), findsOneWidget);
    expect(
      scrollableExtent(tester),
      0,
      reason: 'the whole page has to be visible at once - both offers included',
    );
  });

  testWidgets('both offers are on screen, not below the fold', (tester) async {
    await pumpAt(tester, const Size(375, 667));

    for (final label in ['Upload', 'Create folder']) {
      final rect = tester.getRect(find.widgetWithText(ArDriveButtonNew, label));
      expect(rect.bottom, lessThanOrEqualTo(667),
          reason: '"$label" is off the bottom of the screen');
    }
  });

  /// Grey on grey read as disabled: the secondary token is `solidGrey700` and
  /// the card it sits on is `solidGrey800`, while the *disabled* token is
  /// `solidGrey600` - so the button that worked was less prominent than one
  /// that would not.
  testWidgets('the two offers are drawn as the actions they are',
      (tester) async {
    await pumpAt(tester, const Size(375, 667));

    for (final label in ['Upload', 'Create folder']) {
      final button = tester.widget<ArDriveButtonNew>(
        find.widgetWithText(ArDriveButtonNew, label),
      );
      expect(button.variant, ButtonVariant.primary, reason: label);
    }
  });

  /// The card is drawn on `containerL2`, and the button colour is picked per
  /// theme - so "does it fit" has to be asked in both, not just the one the
  /// tests happened to start in.
  testWidgets('fits in dark mode too', (tester) async {
    await pumpAt(tester, const Size(375, 667), dark: true);

    expect(scrollableExtent(tester), 0);
    for (final label in ['Upload', 'Create folder']) {
      final button = tester.widget<ArDriveButtonNew>(
        find.widgetWithText(ArDriveButtonNew, label),
      );
      expect(button.variant, ButtonVariant.primary, reason: label);
    }
  });

  /// Text scale is the thing that actually breaks stacked layouts, and this
  /// repo has shipped two breakpoints chosen by eye that clipped at some band
  /// of widths nobody had rendered.
  testWidgets('degrades to a scroll rather than an overflow at large text',
      (tester) async {
    await pumpAt(tester, const Size(375, 667), textScale: 1.6);

    // Not asserted to fit: at some scale it cannot, and that is the whole
    // reason the SingleChildScrollView stays. What must not happen is a
    // RenderFlex overflow, which `pumpAndSettle` surfaces as an exception.
    expect(tester.takeException(), isNull);

    // And both offers must still be reachable by scrolling to them.
    for (final label in ['Upload', 'Create folder']) {
      await tester.scrollUntilVisible(
        find.widgetWithText(ArDriveButtonNew, label),
        100,
      );
      expect(find.widgetWithText(ArDriveButtonNew, label), findsOneWidget);
    }
  });

  /// The page used to say "collectively under 100KB", which is neither check
  /// the uploader makes: each file must be under the limit Turbo reports, and
  /// the upload must fit the wallet's free allowance.
  group('states the free upload rule the uploader applies', () {
    testWidgets('on a first drive', (tester) async {
      await pumpAt(tester, const Size(1280, 800));

      expect(
        find.textContaining(
            'Files up to 105 KiB each upload free, while your free allowance '
            'lasts.'),
        findsOneWidget,
      );
      expect(find.textContaining('100KB'), findsNothing);
    });

    testWidgets('on a later drive', (tester) async {
      withDrives([_drive('drive-a'), _drive('drive-b')]);

      // At full scale the test font overflows this page's 221px action cards,
      // on dev's card as much as this one. That is a separate defect; this
      // test is about the copy above them, so it renders smaller.
      await pumpAt(tester, const Size(375, 667), textScale: 0.5);

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

    testWidgets('with the limit Turbo reports, not a fixed one',
        (tester) async {
      when(() => turboUploadService.maxFreeItemSizeBytes).thenReturn(204800);

      await pumpAt(tester, const Size(1280, 800));

      expect(find.textContaining('Files up to 200 KiB each'), findsOneWidget);
    });

    /// The service provided when config turns Turbo uploads off throws for
    /// its limit, and the page must still draw.
    testWidgets('with the configured limit when Turbo uploads are off',
        (tester) async {
      turboUploadService = DontUseUploadService();

      await pumpAt(tester, const Size(1280, 800));

      expect(find.textContaining('Files up to 97.66 KiB each'), findsOneWidget);
    });
  });
}

import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockDrivesCubit extends MockCubit<DrivesState> implements DrivesCubit {}

/// The page a brand new drive opens on: "You're on chain!".
///
/// It has one job - say well done, then offer the two things worth doing next -
/// and on a phone it was doing that job below the fold, because both offers
/// were 283px squares stacked under a heading and a paragraph.
void main() {
  late _MockDrivesCubit drivesCubit;

  setUp(() {
    drivesCubit = _MockDrivesCubit();

    // Exactly one drive is what makes this the new-user page rather than the
    // existing-user one.
    whenListen(
      drivesCubit,
      const Stream<DrivesState>.empty(),
      initialState: DrivesLoadSuccess(
        selectedDriveId: 'drive-a',
        userDrives: [
          Drive(
            id: 'drive-a',
            rootFolderId: 'root',
            ownerAddress: 'owner',
            name: 'My Drive',
            privacy: 'public',
            dateCreated: DateTime(2026, 3, 1),
            lastUpdated: DateTime(2026, 3, 1),
            isHidden: false,
          ),
        ],
        sharedDrives: const [],
        drivesWithAlerts: const [],
        canCreateNewDrive: true,
      ),
    );
  });

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
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
          home: Scaffold(
            body: BlocProvider<DrivesCubit>.value(
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
    );
    await tester.pumpAndSettle();
  }

  /// The measurement that matters, taken rather than assumed: a scroll view
  /// whose content is shorter than its viewport has nowhere to scroll to.
  double scrollableExtent(WidgetTester tester) {
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;

    return position.maxScrollExtent;
  }

  testWidgets('fits on a phone without scrolling', (tester) async {
    // A small-but-real phone viewport: iPhone SE is 375x667.
    await pumpAt(tester, const Size(375, 667));

    expect(find.textContaining("You're on chain!"), findsOneWidget);
    expect(
      scrollableExtent(tester),
      0,
      reason: 'the whole page has to be visible at once - both offers included',
    );
  });

  testWidgets('both offers are on screen, not below the fold', (tester) async {
    await pumpAt(tester, const Size(375, 667));

    for (final label in ['Upload', 'Create Folder']) {
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

    for (final label in ['Upload', 'Create Folder']) {
      final button = tester.widget<ArDriveButtonNew>(
        find.widgetWithText(ArDriveButtonNew, label),
      );
      expect(button.variant, ButtonVariant.primary, reason: label);
    }
  });
}

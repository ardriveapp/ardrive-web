import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/fs_entry_snapshots/fs_entry_snapshots_cubit.dart';
import 'package:ardrive/components/snapshots_tab/snapshots_tab.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/fake_user.dart';
import '../test_utils/mocks.dart';

class _MockSnapshotsCubit extends MockCubit<FsEntrySnapshotsState>
    implements FsEntrySnapshotsCubit {}

void main() {
  late _MockSnapshotsCubit cubit;
  late MockArDriveAuth auth;

  Drive drive({String owner = 'address'}) => Drive(
        id: 'drive',
        rootFolderId: 'root',
        ownerAddress: owner,
        name: 'My Drive',
        privacy: 'public',
        dateCreated: DateTime(2026, 3, 1),
        lastUpdated: DateTime(2026, 3, 1),
        isHidden: false,
      );

  setUp(() {
    cubit = _MockSnapshotsCubit();
    auth = MockArDriveAuth();
    when(() => auth.currentUser).thenReturn(fakeUserJson);
  });

  Future<void> pump(WidgetTester tester, FsEntrySnapshotsState state,
      {String owner = 'address'}) async {
    when(() => cubit.state).thenReturn(state);
    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: RepositoryProvider<ArDriveAuth>.value(
              value: auth,
              child: BlocProvider<FsEntrySnapshotsCubit>.value(
                value: cubit,
                child: SnapshotsTab(drive: drive(owner: owner)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<(String, ButtonVariant)> buttons(WidgetTester tester) => tester
      .widgetList<ArDriveButtonNew>(find.byType(ArDriveButtonNew))
      .map((b) => (b.text, b.variant))
      .toList();

  testWidgets('shows the design system spinner while it loads', (tester) async {
    await pump(tester, const FsEntrySnapshotsLoading());
    expect(find.byType(ArDriveSpinner), findsOneWidget);
  });

  testWidgets('a failure is an empty state that can try again', (tester) async {
    when(() => cubit.refresh()).thenAnswer((_) async {});
    await pump(tester, const FsEntrySnapshotsFailure(errorMessage: 'timeout'));

    expect(find.byType(ArDriveEmptyState), findsOneWidget);
    expect(find.text('timeout'), findsOneWidget);

    await tester.tap(find.byType(ArDriveButtonNew));
    verify(() => cubit.refresh()).called(1);
  });

  testWidgets('a drive that needs a snapshot offers one as the main action',
      (tester) async {
    await pump(
      tester,
      const FsEntrySnapshotsSuccess(
          snapshots: [], shouldRecommendSnapshot: true),
    );

    expect(find.byType(ArDriveEmptyState), findsOneWidget);
    expect(buttons(tester), [('Create snapshot', ButtonVariant.primary)]);
  });

  testWidgets('a small drive only offers one quietly', (tester) async {
    await pump(
      tester,
      const FsEntrySnapshotsSuccess(
          snapshots: [], shouldRecommendSnapshot: false),
    );

    final offered = buttons(tester);
    expect(offered, hasLength(1));
    expect(offered.single.$2, ButtonVariant.secondary);
  });

  testWidgets('nobody but the owner is offered one', (tester) async {
    await pump(
      tester,
      const FsEntrySnapshotsSuccess(
          snapshots: [], shouldRecommendSnapshot: true),
      owner: 'someone-else',
    );

    expect(find.byType(ArDriveButtonNew), findsNothing);
  });
}

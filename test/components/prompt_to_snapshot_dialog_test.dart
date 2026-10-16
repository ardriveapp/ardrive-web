import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/prompt_to_snapshot_dialog.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../test_utils/utils.dart';

class _LoadedDrive extends Mock implements DriveDetailLoadSuccess {}

/// The nudge a slow drive's owner sees. Where publishing is on it offers a
/// drive state artifact rather than a snapshot (D14).
void main() {
  late MockConfigService configService;
  final user = getTestUser();

  Drive driveOwnedBy(String owner) => Drive(
        id: 'drive-id',
        rootFolderId: 'root-folder-id',
        ownerAddress: owner,
        name: 'A slow drive',
        privacy: 'private',
        lastBlockHeight: 0,
        isHidden: false,
        dateCreated: DateTime(2024),
        lastUpdated: DateTime(2024),
      );

  Widget host({
    required bool publishing,
    bool owned = true,
    bool writable = true,
    bool empty = false,
  }) {
    configService = MockConfigService();
    when(() => configService.config).thenReturn(
      AppConfig(
        stripePublishableKey: '',
        allowedDataItemSizeForTurbo: 100,
        enableDriveStatePublishing: publishing,
      ),
    );
    final profile = MockProfileCubit();
    whenListen(profile, const Stream<ProfileState>.empty(),
        initialState: ProfileLoggedIn(user: user, useTurbo: false));
    final loaded = _LoadedDrive();
    when(() => loaded.hasWritePermissions).thenReturn(writable);
    when(() => loaded.driveIsEmpty).thenReturn(empty);
    final detail = MockDriveDetailCubit();
    whenListen(detail, const Stream<DriveDetailState>.empty(),
        initialState: loaded);

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
        home: Provider<ConfigService>.value(
          value: configService,
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ProfileCubit>.value(value: profile),
              BlocProvider<DriveDetailCubit>.value(value: detail),
            ],
            child: Scaffold(
              body: PromptToSnapshotDialog(
                drive:
                    driveOwnedBy(owned ? user.walletAddress : 'someone else'),
                promptToSnapshotBloc: MockPromptToSnapshotBloc(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> expectSnapshotPrompt(WidgetTester tester) async {
    await tester.pumpAndSettle();
    expect(find.text('Create snapshot'), findsOneWidget);
    expect(find.text('Publish drive state'), findsNothing);
  }

  testWidgets('offers to publish the drive state where publishing is on',
      (tester) async {
    await tester.pumpWidget(host(publishing: true));
    await tester.pumpAndSettle();

    expect(find.text('Make this drive load faster'), findsOneWidget);
    expect(find.text('Publish drive state'), findsOneWidget);
    expect(find.text('Create snapshot'), findsNothing);
    expect(find.textContaining('napshot'), findsNothing,
        reason: 'nothing on the prompt mentions snapshots any more');
  });

  testWidgets('offers a snapshot, as before, where publishing is off',
      (tester) async {
    await tester.pumpWidget(host(publishing: false));
    await expectSnapshotPrompt(tester);
  });

  // The menu's own gate, so the nudge never offers what the menu would hide.
  testWidgets('offers a snapshot on a drive this wallet does not own',
      (tester) async {
    await tester.pumpWidget(host(publishing: true, owned: false));
    await expectSnapshotPrompt(tester);
  });

  testWidgets('offers a snapshot where this wallet cannot write',
      (tester) async {
    await tester.pumpWidget(host(publishing: true, writable: false));
    await expectSnapshotPrompt(tester);
  });

  testWidgets('offers a snapshot on an empty drive', (tester) async {
    await tester.pumpWidget(host(publishing: true, empty: true));
    await expectSnapshotPrompt(tester);
  });
}

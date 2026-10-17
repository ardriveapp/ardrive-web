import 'package:ardrive/components/prompt_to_snapshot_dialog.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_utils/utils.dart';

/// The nudge a slow drive's owner sees. Where publishing is on, the snapshot
/// it offers is a drive state artifact (D14), and it says so in the same
/// words as every other "Create snapshot": users see one term.
///
/// Whether it is offered is `createsDriveStateSnapshot`, decided before the
/// prompt opens and tested in `drive_publishes_state_snapshot_test.dart`.
void main() {
  final drive = Drive(
    id: 'drive-id',
    rootFolderId: 'root-folder-id',
    ownerAddress: 'owner',
    name: 'A slow drive',
    privacy: 'private',
    lastBlockHeight: 0,
    isHidden: false,
    dateCreated: DateTime(2024),
    lastUpdated: DateTime(2024),
  );

  Widget host({required bool offersDriveState}) => ArDriveTheme(
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
            body: PromptToSnapshotDialog(
              drive: drive,
              promptToSnapshotBloc: MockPromptToSnapshotBloc(),
              offersDriveState: offersDriveState,
            ),
          ),
        ),
      );

  testWidgets('offers a drive state snapshot where one is offered',
      (tester) async {
    await tester.pumpWidget(host(offersDriveState: true));
    await tester.pumpAndSettle();

    expect(find.text('Make this drive load faster'), findsOneWidget);
    expect(find.text('Create snapshot'), findsOneWidget);
    expect(find.text('Snapshot Recommended'), findsNothing);
    for (final word in ['rive state', 'rtifact', 'ublish']) {
      expect(find.textContaining(word), findsNothing,
          reason: 'users see one term, snapshot, not "$word"');
    }
  });

  testWidgets('offers a snapshot, as before, everywhere else', (tester) async {
    await tester.pumpWidget(host(offersDriveState: false));
    await tester.pumpAndSettle();

    expect(find.text('Create snapshot'), findsOneWidget);
    expect(find.text('Snapshot Recommended'), findsOneWidget);
    expect(find.text('Make this drive load faster'), findsNothing);
  });
}

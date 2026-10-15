import 'package:ardrive/components/prompt_to_snapshot_dialog.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../test_utils/mocks.dart';

/// The nudge a slow drive's owner sees. Where publishing is on it offers a
/// drive state artifact rather than a snapshot (D14).
void main() {
  late MockConfigService configService;

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

  Widget host({required bool publishing}) {
    configService = MockConfigService();
    when(() => configService.config).thenReturn(
      AppConfig(
        stripePublishableKey: '',
        allowedDataItemSizeForTurbo: 100,
        enableDriveStatePublishing: publishing,
      ),
    );
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
          child: Scaffold(
            body: PromptToSnapshotDialog(
              drive: drive,
              promptToSnapshotBloc: MockPromptToSnapshotBloc(),
            ),
          ),
        ),
      ),
    );
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
    await tester.pumpAndSettle();

    expect(find.text('Create snapshot'), findsOneWidget);
    expect(find.text('Publish drive state'), findsNothing);
  });
}

import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/settings/network_settings.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class _MockConfigService extends Mock implements ConfigService {}

class _MockArweaveService extends Mock implements ArweaveService {}

/// The server dialogs opened from Settings count as open dialogs, so
/// auto-sync and multi-select know a dialog is up.
void main() {
  final tracker = ActivityTracker();
  final config = _MockConfigService();
  final arweave = _MockArweaveService();

  setUp(() {
    when(() => config.config).thenReturn(AppConfig(
      useTurboUpload: true,
      useTurboPayment: true,
      allowedDataItemSizeForTurbo: 107520,
      stripePublishableKey: '',
    ));
  });

  Future<void> open(
    WidgetTester tester,
    Future<void> Function(BuildContext) show,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<ActivityTracker>.value(value: tracker),
            RepositoryProvider<ConfigService>.value(value: config),
            RepositoryProvider<ArweaveService>.value(value: arweave),
          ],
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  for (final entry in {
    'GraphQL server': showGraphQLServerDialog,
    'Turbo services': showTurboServicesDialog,
  }.entries) {
    testWidgets('the ${entry.key} dialog counts as an open dialog',
        (tester) async {
      await open(tester, entry.value);

      expect(tracker.isMultiSelectEnabled, isFalse);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tracker.isMultiSelectEnabled, isTrue);
    });
  }
}

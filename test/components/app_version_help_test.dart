import 'package:ardrive/components/app_version_widget.dart';
import 'package:ardrive/components/settings_popover.dart';
import 'package:ardrive/components/side_bar.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _MockPreferences extends Mock implements UserPreferencesRepository {}

class _MockConfigService extends Mock implements ConfigService {}

class _RecordingUrlLauncher extends UrlLauncherPlatform {
  final List<String> launched = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    launched.add(url);
    return true;
  }
}

/// The version left the sidebar and the sign-in page for Help, where a
/// reader asking for support is, with a link to what changed in it.
void main() {
  late _RecordingUrlLauncher launcher;

  setUp(() {
    launcher = _RecordingUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
    PackageInfo.setMockInitialValues(
      appName: 'ArDrive',
      packageName: 'ardrive',
      version: '2.90.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group("What's new", () {
    test('a production build opens its own release, which is tagged', () {
      expect(
        whatsNewUrl('2.90.0', Flavor.production),
        'https://github.com/ardriveapp/ardrive-web/releases/tag/v2.90.0',
      );
    });

    test('staging and development builds, never tagged, open the releases', () {
      for (final flavor in [Flavor.staging, Flavor.development]) {
        expect(
          whatsNewUrl('2.90.0', flavor),
          'https://github.com/ardriveapp/ardrive-web/releases',
          reason: flavor.name,
        );
      }
    });
  });

  Future<void> pumpHelp(WidgetTester tester, Flavor flavor) async {
    final config = _MockConfigService();
    when(() => config.flavor).thenReturn(flavor);
    final preferences = _MockPreferences();
    when(() => preferences.loadSyncHistory()).thenAnswer((_) async => []);

    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ConfigService>.value(value: config),
          RepositoryProvider<UserPreferencesRepository>.value(
            value: preferences,
          ),
          ChangeNotifierProvider<ActivityTracker>(
            create: (_) => ActivityTracker(),
          ),
        ],
        child: ArDriveApp(
          builder: (context) => MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en', '')],
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showSupportModal(context: context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  for (final (flavor, url) in [
    (
      Flavor.production,
      'https://github.com/ardriveapp/ardrive-web/releases/tag/v2.90.0'
    ),
    (Flavor.staging, 'https://github.com/ardriveapp/ardrive-web/releases'),
  ]) {
    testWidgets("Help says the version, and What's new opens ${flavor.name}'s",
        (tester) async {
      await pumpHelp(tester, flavor);

      expect(find.byType(AppVersionHelpLine), findsOneWidget);
      // With its build number, off the web.
      expect(find.textContaining('Version 2.90.0'), findsOneWidget);
      final link = find.byWidgetPredicate(
        (w) => w is ArDriveLink && w.text == "What's new",
      );
      expect(link, findsOneWidget);
      expect(tester.widget<ArDriveLink>(link).external, isTrue,
          reason: 'it leaves the app, so it has the new-window icon');

      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      await tester.tap(link);
      await tester.pump();

      expect(launcher.launched, [url]);
    });
  }

  /// A signed-out reader has no Help, so the sign-in panel's settings menu
  /// ends with the same line.
  for (final (flavor, url) in [
    (
      Flavor.production,
      'https://github.com/ardriveapp/ardrive-web/releases/tag/v2.90.0'
    ),
    (Flavor.development, 'https://github.com/ardriveapp/ardrive-web/releases'),
  ]) {
    testWidgets(
        'the sign-in settings menu ends with the version, for ${flavor.name}',
        (tester) async {
      final config = _MockConfigService();
      when(() => config.flavor).thenReturn(flavor);
      final preferences = _MockPreferences();
      when(() => preferences.watch())
          .thenAnswer((_) => const Stream<UserPreferences>.empty());
      when(() => preferences.currentPreferences).thenReturn(null);

      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<ConfigService>.value(value: config),
            RepositoryProvider<UserPreferencesRepository>.value(
              value: preferences,
            ),
          ],
          child: ArDriveApp(
            builder: (context) => const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: [Locale('en', '')],
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SettingsSubmenu(child: Text('cog')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('cog'));
      await tester.pumpAndSettle();

      expect(find.byType(AppVersionHelpLine), findsOneWidget);
      expect(find.textContaining('Version 2.90.0'), findsOneWidget);
      // The last line of the menu.
      final version = tester.getTopLeft(find.byType(AppVersionHelpLine)).dy;
      for (final item in ['Set gateway', 'Set Turbo services']) {
        expect(tester.getTopLeft(find.text(item)).dy, lessThan(version));
      }

      final link = find.byWidgetPredicate(
        (w) => w is ArDriveLink && w.text == "What's new",
      );
      await tester.tap(link);
      await tester.pump();
      expect(launcher.launched, [url]);
    });
  }
}

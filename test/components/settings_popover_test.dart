import 'package:ardrive/components/settings_popover.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _MockPreferences extends Mock implements UserPreferencesRepository {}

class _MockConfigService extends Mock implements ConfigService {}

/// The sync-on-login row in the settings menu: its pointer and hover fill
/// span the row, so a click anywhere on it flips the switch.
void main() {
  late _MockPreferences preferences;

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'ArDrive',
      packageName: 'ardrive',
      version: '2.90.0',
      buildNumber: '1',
      buildSignature: '',
    );
    preferences = _MockPreferences();
    when(() => preferences.watch())
        .thenAnswer((_) => const Stream<UserPreferences>.empty());
    when(() => preferences.currentPreferences).thenReturn(null);
    when(() => preferences.saveSyncAllDrivesOnLogin(any()))
        .thenAnswer((_) async {});
  });

  Future<void> openMenu(WidgetTester tester) async {
    final config = _MockConfigService();
    when(() => config.flavor).thenReturn(Flavor.production);

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
  }

  Finder row() => find.ancestor(
        of: find.byType(ArDriveToggleSwitch),
        matching: find.byType(ArDriveHoverWidget),
      );

  testWidgets('a click on the row away from the switch flips it',
      (tester) async {
    await openMenu(tester);

    // The empty end of the row, past the label, and its padding before the
    // switch: both drew the pointer and the hover fill and did nothing.
    final box = tester.getRect(row());
    for (final spot in [
      Offset(box.right - 4, box.center.dy),
      Offset(box.left + 4, box.center.dy),
    ]) {
      await tester.tapAt(spot);
      await tester.pumpAndSettle();
    }

    verify(() => preferences.saveSyncAllDrivesOnLogin(true)).called(2);
    // A setting, not a command: the menu stays open.
    expect(find.byType(ArDriveToggleSwitch), findsOneWidget);
  });

  testWidgets('a click on the switch itself flips it once', (tester) async {
    await openMenu(tester);

    await tester.tap(find.text('Sync all drives on login'));
    await tester.pumpAndSettle();

    verify(() => preferences.saveSyncAllDrivesOnLogin(true)).called(1);
  });

  testWidgets('the row reaches a screen reader as one switch', (tester) async {
    final semantics = tester.ensureSemantics();
    await openMenu(tester);

    expect(
      tester.getSemantics(find.byType(ArDriveToggleSwitch)),
      matchesSemantics(
        label: 'Sync all drives on login',
        isToggled: false,
        hasToggledState: true,
        isEnabled: true,
        hasEnabledState: true,
        hasTapAction: true,
      ),
    );
    // And no second, unlabelled tap target around it.
    final node = tester.getSemantics(row());
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse,
        reason: 'the row adds no tap of its own to the tree');

    semantics.dispose();
  });
}

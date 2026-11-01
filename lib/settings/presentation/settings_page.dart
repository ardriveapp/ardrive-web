import 'package:ardrive/account/presentation/account_page.dart';
import 'package:ardrive/app_shell.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/components/list_page/list_page_layout.dart';
import 'package:ardrive/drives_list/presentation/open_drive_on_selection.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/settings/network_settings.dart';
import 'package:ardrive/theme/theme_switcher_bloc.dart';
import 'package:ardrive/theme/theme_switcher_state.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

/// The Settings page in the app shell: a drive chosen in the sidebar opens
/// it, as on the Account and Billing pages.
class SettingsShell extends StatelessWidget {
  const SettingsShell({super.key, required this.onOpenDrive});

  final void Function(String driveId) onOpenDrive;

  @override
  Widget build(BuildContext context) {
    return OpenDriveOnSelection(
      selections: context.read<DrivesCubit>().driveSelections,
      onOpenDrive: onOpenDrive,
      child: const AppShell(page: SettingsPage()),
    );
  }
}

/// Settings: appearance, sync, uploads and the network. Full screen with a
/// back arrow on a phone; in the main area on desktop.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final title = appLocalizationsOf(context).settingsPageTitle;

    return ScreenTypeLayout.builder(
      mobile: (context) => PhonePage(
        title: title,
        backKey: const Key('settingsBack'),
        onBack: () => context.read<AppRouterDelegate>().closeSettings(),
        child: const SettingsSections(),
      ),
      desktop: (context) => ListPageChrome(
        child: ReadablePageBody(
          title: title,
          child: const SettingsSections(),
        ),
      ),
    );
  }
}

/// The page's sections. Reads the config and preferences from the app's
/// services and writes straight back to them.
class SettingsSections extends StatefulWidget {
  const SettingsSections({super.key});

  @override
  State<SettingsSections> createState() => _SettingsSectionsState();
}

class _SettingsSectionsState extends State<SettingsSections> {
  /// What this build ships with, for the Reset buttons. Null until read, and
  /// when it can't be: a row then offers no Reset rather than a guess.
  AppConfig? _defaults;

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  Future<void> _loadDefaults() async {
    try {
      final defaults = await context.read<ConfigService>().loadDefaultConfig();
      if (mounted) setState(() => _defaults = defaults);
    } catch (_) {
      // No defaults to reset to.
    }
  }

  AppConfig get _config => context.read<ConfigService>().config;

  Future<void> _update(AppConfig Function(AppConfig config) change) async {
    final configService = context.read<ConfigService>();
    await configService.updateAppConfig(change(configService.config));
    if (mounted) setState(() {});
  }

  /// Runs a change to the network and shows the result, or says it failed:
  /// a reset reaches the gateway and can throw.
  Future<void> _then(Future<void> Function() change) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final failed = appLocalizationsOf(context).settingsNetworkChangeFailed;
    try {
      await change();
    } catch (e, stackTrace) {
      logger.e('Could not change a network setting', e, stackTrace);
      if (messenger != null) {
        showArDriveToast(
          messenger,
          text: failed,
          type: ArDriveStatusType.error,
        );
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final config = _config;
    final defaults = _defaults;
    final minutes = (config.autoSyncIntervalInSeconds / 60).round();

    final gateway = config.arweaveGatewayForDataRequest.url;
    final graphQL = graphQLServerOf(config);
    final uploadUrl = config.defaultTurboUploadUrl ?? '';
    final paymentUrl = config.defaultTurboPaymentUrl ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageSection(
          title: strings.settingsAppearanceSection,
          rows: const [_ThemeRow()],
        ),
        PageSection(
          title: strings.sync,
          rows: [
            _ToggleRow(
              key: const Key('settingsAutoSync'),
              title: strings.settingsAutoSync,
              note: strings.settingsAutoSyncNote(minutes < 1 ? 1 : minutes),
              value: config.autoSync,
              onChanged: (value) => _update((c) => c.copyWith(autoSync: value)),
            ),
            StreamBuilder<UserPreferences>(
              stream: context.read<UserPreferencesRepository>().watch(),
              builder: (context, snapshot) {
                final repo = context.read<UserPreferencesRepository>();
                final value = snapshot.data?.syncAllDrivesOnLogin ??
                    repo.currentPreferences?.syncAllDrivesOnLogin ??
                    false;
                return _ToggleRow(
                  key: const Key('settingsSyncOnSignIn'),
                  title: strings.settingsSyncOnSignIn,
                  note: strings.settingsSyncOnSignInNote,
                  value: value,
                  onChanged: repo.saveSyncAllDrivesOnLogin,
                );
              },
            ),
            _ToggleRow(
              key: const Key('settingsSyncSnapshots'),
              title: strings.settingsSyncSnapshots,
              note: strings.settingsSyncSnapshotsNote,
              value: config.enableSyncFromSnapshot,
              onChanged: (value) =>
                  _update((c) => c.copyWith(enableSyncFromSnapshot: value)),
            ),
          ],
        ),
        PageSection(
          title: strings.settingsUploadsSection,
          rows: [
            _ToggleRow(
              key: const Key('settingsThumbnails'),
              title: strings.settingsThumbnails,
              note: strings.settingsThumbnailsNote,
              value: config.uploadThumbnails,
              onChanged: (value) =>
                  _update((c) => c.copyWith(uploadThumbnails: value)),
            ),
          ],
        ),
        PageSection(
          title: strings.settingsNetworkSection,
          rows: [
            _NetworkRow(
              name: 'settingsGateway',
              title: strings.settingsGateway,
              note: strings.settingsGatewayNote,
              addresses: [gateway],
              onChange: () => _then(() => showGatewayDialog(context)),
              onReset: defaults == null ||
                      gateway == defaults.arweaveGatewayForDataRequest.url
                  ? null
                  : () => _then(() => resetGateway(context, defaults)),
            ),
            _NetworkRow(
              name: 'settingsGraphQLServer',
              title: strings.settingsGraphQLServer,
              note: strings.settingsGraphQLServerNote,
              addresses: [graphQL],
              onChange: () => _then(() => showGraphQLServerDialog(context)),
              onReset: defaults == null || graphQL == graphQLServerOf(defaults)
                  ? null
                  : () => _then(() => resetGraphQLServer(context, defaults)),
            ),
            _NetworkRow(
              name: 'settingsTurboServices',
              title: strings.settingsTurboServices,
              note: strings.settingsTurboServicesNote,
              addresses: [
                if (uploadUrl.isNotEmpty) uploadUrl,
                if (paymentUrl.isNotEmpty) paymentUrl,
              ],
              onChange: () => _then(() => showTurboServicesDialog(context)),
              onReset: defaults == null ||
                      (uploadUrl == (defaults.defaultTurboUploadUrl ?? '') &&
                          paymentUrl == (defaults.defaultTurboPaymentUrl ?? ''))
                  ? null
                  : () => _then(() => resetTurboServices(context, defaults)),
            ),
          ],
          footer: Padding(
            padding: const EdgeInsets.only(
              left: ArDriveSpacing.xxs,
              top: ArDriveSpacing.xs,
            ),
            child: Text(
              strings.settingsNetworkFooter,
              style: typography.paragraphSmall(
                color: colors.textLow,
                fontWeight: ArFontWeight.book,
              ),
            ),
          ),
        ),
        const SizedBox(height: ArDriveSpacing.md),
      ],
    );
  }
}

/// A setting's one-line explanation, in the colour every row uses for it.
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: ArDriveTypographyNew.of(context).paragraphSmall(
        color: ArDriveTheme.of(context).themeData.colorTokens.textMid,
        fontWeight: ArFontWeight.book,
      ),
    );
  }
}

/// Light or Dark. The theme bloc only knows those two; there is no
/// "match my device".
class _ThemeRow extends StatelessWidget {
  const _ThemeRow();

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);

    return BlocBuilder<ThemeSwitcherBloc, ThemeSwitcherState>(
      builder: (context, state) {
        final dark = switch (state) {
          ThemeSwitcherDarkTheme() => true,
          ThemeSwitcherLightTheme() => false,
          _ => null,
        };
        return PageRow(
          title: strings.settingsTheme,
          subtitle: _Note(strings.settingsThemeNote),
          trailing: ArDriveSegmentedControl<bool>(
            key: const Key('settingsTheme'),
            selected: dark,
            segments: [
              ArDriveSegment(value: false, label: strings.settingsThemeLight),
              ArDriveSegment(value: true, label: strings.settingsThemeDark),
            ],
            onSelected: (wantsDark) {
              if (wantsDark != dark) {
                context.read<ThemeSwitcherBloc>().add(ChangeTheme());
              }
            },
          ),
        );
      },
    );
  }
}

/// A switch with its label above a one-line explanation. The switch carries
/// the label, so a screen reader hears one named control.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    super.key,
    required this.title,
    required this.note,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String note;
  final bool value;
  final Future<void> Function(bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ArDriveSpacing.md,
          vertical: ArDriveSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ArDriveToggleSwitch(
              alignRight: true,
              value: value,
              text: title,
              textStyle: ArDriveTypographyNew.of(context).paragraphNormal(
                color: colors.textHigh,
                fontWeight: ArFontWeight.semiBold,
              ),
              onChanged: onChanged,
            ),
            const SizedBox(height: ArDriveSpacing.xxs),
            _Note(note),
          ],
        ),
      ),
    );
  }
}

/// A server the app talks to: what it is for, where it points now (in
/// monospace), Change, and Reset to default when it differs from the shipped
/// address.
class _NetworkRow extends StatelessWidget {
  const _NetworkRow({
    required this.name,
    required this.title,
    required this.note,
    required this.addresses,
    required this.onChange,
    required this.onReset,
  });

  /// Prefix of the keys of this row's buttons.
  final String name;
  final String title;
  final String note;
  final List<String> addresses;
  final VoidCallback onChange;

  /// Null when the address is the shipped one, or the shipped one is unknown.
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return PageRow(
      title: title,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Note(note),
          for (final address in addresses)
            Padding(
              padding: const EdgeInsets.only(top: ArDriveSpacing.xxs),
              child: Text(
                address,
                style: typography.code(fontSize: 13, color: colors.textMid),
              ),
            ),
          const SizedBox(height: ArDriveSpacing.xs),
          Wrap(
            spacing: ArDriveSpacing.sm,
            runSpacing: ArDriveSpacing.xs,
            children: [
              PageRowButton(
                key: Key('${name}Change'),
                text: strings.settingsChange,
                onPressed: onChange,
              ),
              if (onReset != null)
                PageRowButton(
                  key: Key('${name}Reset'),
                  text: strings.settingsResetToDefault,
                  onPressed: onReset!,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

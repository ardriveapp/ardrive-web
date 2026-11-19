import 'package:ardrive/components/app_version_widget.dart';
import 'package:ardrive/settings/network_settings.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SettingsSubmenu extends StatelessWidget {
  final Widget child;

  const SettingsSubmenu({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ArDriveSubmenu(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        ArDriveSubmenuItem(
          onClick: () {
            showGatewayDialog(context);
          },
          widget: ArDriveHoverWidget(
            hoverColor:
                ArDriveTheme.of(context).themeData.dropdownTheme.hoverColor,
            defaultColor: ArDriveTheme.of(context)
                .themeData
                .dropdownTheme
                .backgroundColor,
            child: ArDriveDropdownItemTile(
              name: appLocalizationsOf(context).settingsSetGateway,
            ),
          ),
        ),
        ArDriveSubmenuItem(
          onClick: () {
            showGraphQLServerDialog(context);
          },
          widget: ArDriveHoverWidget(
            hoverColor:
                ArDriveTheme.of(context).themeData.dropdownTheme.hoverColor,
            defaultColor: ArDriveTheme.of(context)
                .themeData
                .dropdownTheme
                .backgroundColor,
            child: ArDriveDropdownItemTile(
              name: appLocalizationsOf(context).settingsSetGraphQLServer,
            ),
          ),
        ),
        ArDriveSubmenuItem(
          onClick: () {
            showTurboServicesDialog(context);
          },
          widget: ArDriveHoverWidget(
            hoverColor:
                ArDriveTheme.of(context).themeData.dropdownTheme.hoverColor,
            defaultColor: ArDriveTheme.of(context)
                .themeData
                .dropdownTheme
                .backgroundColor,
            child: ArDriveDropdownItemTile(
              name: appLocalizationsOf(context).settingsSetTurboServices,
            ),
          ),
        ),
        ArDriveSubmenuItem(
          widget: StreamBuilder<UserPreferences>(
            stream: context.read<UserPreferencesRepository>().watch(),
            builder: (context, streamSnapshot) {
              final repo = context.read<UserPreferencesRepository>();
              final syncAllDrivesOnLogin =
                  streamSnapshot.data?.syncAllDrivesOnLogin ??
                      repo.currentPreferences?.syncAllDrivesOnLogin ??
                      false;
              // The whole row flips the switch, as its pointer and hover fill
              // say it will. A tap on the switch itself is the switch's: the
              // inner detector wins, so it flips once. The row's tap is left
              // out of the semantics tree, where the switch is already one
              // control with its label and state.
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: () =>
                    repo.saveSyncAllDrivesOnLogin(!syncAllDrivesOnLogin),
                child: ArDriveHoverWidget(
                  hoverColor: ArDriveTheme.of(context)
                      .themeData
                      .dropdownTheme
                      .hoverColor,
                  defaultColor: ArDriveTheme.of(context)
                      .themeData
                      .dropdownTheme
                      .backgroundColor,
                  child: SizedBox(
                    height: 48,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18.0),
                      child: ArDriveToggleSwitch(
                        value: syncAllDrivesOnLogin,
                        text: appLocalizationsOf(context).syncAllDrivesOnLogin,
                        onChanged: (value) {
                          repo.saveSyncAllDrivesOnLogin(value);
                        },
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // The version, for a signed-out reader, who has no Help to find it
        // in. A line to read, with one link in it, rather than an action.
        ArDriveSubmenuItem(
          widget: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: AppVersionHelpLine(quiet: true),
          ),
        ),
      ],
      child: child,
    );
  }
}

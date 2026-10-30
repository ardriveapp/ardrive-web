import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/theme/theme_switcher_bloc.dart';
import 'package:ardrive/theme/theme_switcher_state.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Switches between the light and dark themes: a moon in light, a sun in
/// dark, both ardrive_ui's own (the sun was Material's, a different set). An
/// icon button, so a screen reader hears a named button; it was a bare
/// gesture with a tooltip.
class IconThemeSwitcher extends StatelessWidget {
  const IconThemeSwitcher({super.key, this.color});

  /// The sun's colour in dark; the moon is always iconLow.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return BlocConsumer<ThemeSwitcherBloc, ThemeSwitcherState>(
      listener: (context, state) {
        if (state is ThemeSwitcherDarkTheme) {
          PlausibleEventTracker.trackClickThemeSwitcherDark(
            PlausiblePageView.loginPage,
          );
        } else {
          PlausibleEventTracker.trackClickThemeSwitcherLight(
            PlausiblePageView.loginPage,
          );
        }
      },
      builder: (context, state) {
        if (state is ThemeSwitcherInProgress) {
          return const SizedBox.shrink();
        }
        return ArDriveIconButton(
          tooltip: appLocalizationsOf(context).changeTheme,
          icon: state is ThemeSwitcherDarkTheme
              ? ArDriveIcons.sun(color: color ?? colorTokens.iconLow)
              : ArDriveIcons.moon(color: colorTokens.iconLow),
          onPressed: () => context.read<ThemeSwitcherBloc>().add(ChangeTheme()),
        );
      },
    );
  }
}

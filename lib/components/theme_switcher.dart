import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/theme/theme_switcher_bloc.dart';
import 'package:ardrive/theme/theme_switcher_state.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ThemeSwitcher extends StatelessWidget {
  const ThemeSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    return HoverWidget(
      tooltip: appLocalizationsOf(context).changeTheme,
      child: GestureDetector(
        onTap: () {
          context.read<ThemeSwitcherBloc>().add(ChangeTheme());
        },
        child: BlocBuilder<ThemeSwitcherBloc, ThemeSwitcherState>(
          builder: (context, state) {
            if (state is ThemeSwitcherInProgress) {
              return const SizedBox.shrink();
            }

            return Text(
              state is ThemeSwitcherDarkTheme?
                  ? appLocalizationsOf(context).lightModeEmphasized
                  : appLocalizationsOf(context).darkModeEmphasized,
              style: ArDriveTypography.body.buttonNormalBold(),
            );
          },
        ),
      ),
    );
  }
}

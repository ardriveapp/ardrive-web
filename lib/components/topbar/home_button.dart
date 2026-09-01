import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

/// The way back to the list of drives, in the one place that exists on every
/// screen and both breakpoints.
///
/// It lived in the sidebar first, which was the wrong container: the sidebar
/// already lists every drive, so an entry pointing at "all drives" sat
/// directly above a list of all your drives and read as redundant however it
/// was styled. Then only in the explorer's breadcrumb, which is built solely
/// by `_desktopView` - so a phone had no way back at all.
///
/// This slot held the help button, which has moved into the account menu
/// alongside log out, where a reader looks for it anyway.
class HomeButtonTopBar extends StatelessWidget {
  const HomeButtonTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    // Only offered to somebody who can actually get there - the same rule the
    // router applies before it will draw the list at all.
    if (!AppRouterDelegate.canShowDrivesList(
      context.watch<ProfileCubit>().state,
    )) {
      return const SizedBox.shrink();
    }

    return HoverWidget(
      tooltip: appLocalizationsOf(context).yourDrives,
      child: ArDriveClickArea(
        child: GestureDetector(
          onTap: () => context.read<AppRouterDelegate>().showDrivesList(),
          // The design system's icon font has no house, so this is Material's
          // until one is cut. Sized to the icons either side of it.
          child: Icon(
            Icons.home_outlined,
            size: 24,
            color: colorTokens.textMid,
          ),
        ),
      ),
    );
  }
}

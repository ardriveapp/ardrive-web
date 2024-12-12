import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/components/topbar/help_button.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/search/search_modal.dart';
import 'package:ardrive/search/search_text_field.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_custom_event_properties.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController();

    return SizedBox(
      height: 110,
      width: double.maxFinite,
      child: Padding(
        padding: const EdgeInsets.only(right: 17.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: SearchTextField(
                  controller: controller,
                  onFieldSubmitted: (query) {
                    showSearchModalDesktop(
                      context: context,
                      driveDetailCubit: context.read<DriveDetailCubit>(),
                      controller: controller,
                      drivesCubit: context.read<DrivesCubit>(),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 24),
            const Spacer(),
            const GlobalHideToggleButton(),
            const SizedBox(width: 8),
            const SyncButton(),
            const SizedBox(width: 8),
            const HelpButtonTopBar(),
            const SizedBox(width: 24),
            const ProfileCard(),
          ],
        ),
      ),
    );
  }
}

class GlobalHideToggleButton extends StatelessWidget {
  const GlobalHideToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GlobalHideBloc, GlobalHideState>(
      builder: (context, hideState) {
        if (!hideState.userHasHiddenDrive) {
          return const SizedBox.shrink();
        }

        final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

        final tooltip = hideState is ShowingHiddenItems
            ? 'Hide hidden items'
            : 'Show hidden items';

        final icon = hideState is ShowingHiddenItems
            ? ArDriveIcons.eyeOpen(
                color: colorTokens.textMid,
              )
            : ArDriveIcons.eyeClosed(
                color: colorTokens.textMid,
              );

        return ArDriveIconButton(
          tooltip: tooltip,
          icon: icon,
          onPressed: () {
            context.read<GlobalHideBloc>().add(
                  hideState is ShowingHiddenItems
                      ? HideItems(
                          userHasHiddenItems: hideState.userHasHiddenDrive)
                      : ShowItems(
                          userHasHiddenItems: hideState.userHasHiddenDrive,
                        ),
                );
          },
        );
      },
    );
  }
}

class SyncButton extends StatelessWidget {
  const SyncButton({super.key});

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return HoverWidget(
      tooltip: appLocalizationsOf(context).resyncTooltip,
      child: ArDriveDropdown(
        anchor: const Aligned(
          follower: Alignment.topRight,
          target: Alignment.bottomRight,
        ),
        items: [
          ArDriveDropdownItem(
            onClick: () {
              context.read<SyncCubit>().startSync(deepSync: false);
              context.read<ProfileNameBloc>().add(RefreshProfileName());
              PlausibleEventTracker.trackResync(type: ResyncType.resync);
            },
            content: ArDriveDropdownItemTile(
              name: appLocalizationsOf(context).resync,
              icon: ArDriveIcons.refresh(
                color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
              ),
            ),
          ),
          ArDriveDropdownItem(
            onClick: () {
              context.read<SyncCubit>().startSync(deepSync: true);
              context.read<ProfileNameBloc>().add(RefreshProfileName());
              PlausibleEventTracker.trackResync(type: ResyncType.deepResync);
            },
            content: ArDriveDropdownItemTile(
              name: appLocalizationsOf(context).deepResync,
              icon: ArDriveIcons.cloudSync(
                color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
              ),
            ),
          ),
        ],
        child: ArDriveIcons.refresh(color: colorTokens.textMid),
      ),
    );
  }
}

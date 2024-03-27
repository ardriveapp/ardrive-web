import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/components/keyboard_handler.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/gift/reedem_button.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_custom_event_properties.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ArDriveTheme.of(context).themeData;
    final textTheme = theme.copyWith(
      textFieldTheme: theme.textFieldTheme.copyWith(
        inputBackgroundColor: theme.colors.themeBgCanvas,
        labelColor: theme.colors.themeFgDefault,
        requiredLabelColor: theme.colors.themeFgDefault,
        inputTextStyle: theme.textFieldTheme.inputTextStyle.copyWith(
          color: theme.colors.themeFgMuted,
          fontWeight: FontWeight.w600,
          height: 1.5,
          fontSize: 16,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 8,
        ),
        labelStyle: TextStyle(
          color: theme.colors.themeFgDefault,
          fontWeight: FontWeight.w600,
          height: 1.5,
          fontSize: 16,
        ),
      ),
    );
    return SizedBox(
      height: 110,
      width: double.maxFinite,
      child: Padding(
        padding: const EdgeInsets.only(right: 24.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: ArDriveTheme(
                themeData: textTheme,
                child: ArDriveTextField(
                  hintText: 'Search',
                  suffixIcon: const Icon(Icons.search),
                  onFieldSubmitted: (s) {
                    showArDriveDialog(
                      context,
                      content: FileSearchModal(
                        initialQuery: s,
                        driveDetailCubit: context.read<DriveDetailCubit>(),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SyncButton(),
            const SizedBox(width: 24),
            const RedeemButton(),
            const SizedBox(width: 24),
            const ProfileCard(),
          ],
        ),
      ),
    );
  }
}

class SyncButton extends StatelessWidget {
  const SyncButton({super.key});

  @override
  Widget build(BuildContext context) {
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
                PlausibleEventTracker.trackResync(type: ResyncType.deepResync);
              },
              content: ArDriveDropdownItemTile(
                name: appLocalizationsOf(context).deepResync,
                icon: ArDriveIcons.cloudSync(
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeFgDefault,
                ),
              )),
        ],
        child: ArDriveIcons.refresh(
          color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
        ),
      ),
    );
  }
}

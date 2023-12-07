// implement a widget that has 145 of height and maximum widget, and has a row as child
import 'package:ardrive/blocs/sync/sync_cubit.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
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
    return const SizedBox(
      height: 110,
      width: double.maxFinite,
      child: Padding(
        padding: EdgeInsets.only(right: 24.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SyncButton(),
            SizedBox(width: 24),
            ProfileCard(),
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
              context.read<SyncCubit>().startSync(syncDeep: false);
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
                context.read<SyncCubit>().startSync(syncDeep: true);
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

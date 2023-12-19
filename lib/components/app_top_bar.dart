// implement a widget that has 145 of height and maximum widget, and has a row as child
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/gift/reedem_button.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      width: double.maxFinite,
      child: Padding(
        padding: const EdgeInsets.only(right: 24.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ShowHiddenFilesButton(
              driveDetailCubit: context.read<DriveDetailCubit>(),
            ),
            const SizedBox(width: 24),
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

class ShowHiddenFilesButton extends StatelessWidget {
  final DriveDetailCubit driveDetailCubit;

  const ShowHiddenFilesButton({
    super.key,
    required this.driveDetailCubit,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DriveDetailCubit, DriveDetailState>(
      bloc: driveDetailCubit,
      builder: (context, state) {
        if (state is DriveDetailLoadSuccess) {
          final isShowingHiddenFiles = state.isShowingHiddenFiles;
          return HoverWidget(
            tooltip: isShowingHiddenFiles
                ? 'Hide hidden files'
                : 'Show hidden files',
            child: ArDriveIconButton(
              icon: isShowingHiddenFiles
                  ? ArDriveIcons.eyeOpen()
                  : ArDriveIcons.eyeClosed(),
              onPressed: () {
                driveDetailCubit.toggleHiddenFiles();
              },
            ),
          );
        } else {
          return const SizedBox();
        }
      },
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
              context.read<SyncCubit>().startSync(
                    syncDeep: false,
                  );
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
                context.read<SyncCubit>().startSync(
                      syncDeep: true,
                    );
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

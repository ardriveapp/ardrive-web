// implement a widget that has 145 of height and maximum widget, and has a row as child
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/sync/sync_cubit.dart';
import 'package:ardrive/components/profile_card.dart';
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
            const SyncButton(),
            const SizedBox(width: 24),
            ProfileCard(
              walletAddress:
                  context.read<ArDriveAuth>().currentUser?.walletAddress ?? '',
            ),
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
    return ArDriveDropdown(
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
          content: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                ArDriveIcons.sync(
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeFgDefault,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  appLocalizationsOf(context).resync,
                ),
              ],
            ),
          ),
        ),
        ArDriveDropdownItem(
          onClick: () {
            context.read<SyncCubit>().startSync(
                  syncDeep: true,
                );
          },
          content: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                const Icon(
                  Icons.cloud_sync,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  appLocalizationsOf(context).deepResync,
                ),
              ],
            ),
          ),
        ),
      ],
      child: ArDriveIcons.sync(
        color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
        size: 24,
      ),
    );
  }
}

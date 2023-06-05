import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/components/details_panel.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ProfileCard extends StatelessWidget {
  const ProfileCard({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) => state is ProfileLoggedIn
          ? _loggedInView(context)
          : _notLoggedInView(context),
    );
  }

  Widget _notLoggedInView(BuildContext context) {
    return InkWell(
      onTap: () {
        context.read<ProfileCubit>().logoutProfile();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
            width: 2,
          ),
        ),
        width: 101,
        height: 40,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Text(
              appLocalizationsOf(context).login,
              style: ArDriveTypography.body.buttonNormalBold(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loggedInView(BuildContext context) {
    final state = context.read<ProfileCubit>().state as ProfileLoggedIn;
    final walletAddress = state.walletAddress;

    return ArDriveClickArea(
      tooltip: appLocalizationsOf(context).profile,
      child: ArDriveDropdown(
        width: 205,
        anchor: const Aligned(
          follower: Alignment.topRight,
          target: Alignment.bottomRight,
          offset: Offset(0, 4),
        ),
        items: [
          ArDriveDropdownItem(
            onClick: () {
              openUrl(
                url:
                    'https://viewblock.io/arweave/address/${state.walletAddress}',
              );
            },
            content: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (walletAddress.isNotEmpty)
                    Text(
                      '${walletAddress.substring(0, 6)}...${walletAddress.substring(walletAddress.length - 5)}',
                      style: ArDriveTypography.body.buttonNormalBold().copyWith(
                            decoration: TextDecoration.underline,
                          ),
                    ),
                  CopyButton(
                    size: 24,
                    text: walletAddress,
                    showCopyText: false,
                  ),
                ],
              ),
            ),
          ),
          ArDriveDropdownItem(
            onClick: () {
              Clipboard.setData(
                ClipboardData(
                  text: utils.winstonToAr(state.walletBalance).toString(),
                ),
              );
            },
            content: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    appLocalizationsOf(context).arBalance,
                    style: ArDriveTypography.body.buttonNormalBold(),
                  ),
                  Text(
                    '${double.tryParse(utils.winstonToAr(state.walletBalance))?.toStringAsFixed(5) ?? 0} AR',
                    style: ArDriveTypography.body.buttonNormalBold(),
                  ),
                ],
              ),
            ),
          ),
          ArDriveDropdownItem(
            content: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    appLocalizationsOf(context).logout,
                    style: ArDriveTypography.body.buttonNormalBold(),
                  ),
                  HoverWidget(child: ArDriveIcons.logout()),
                ],
              ),
            ),
            onClick: () async {
              context.read<ArDriveAuth>().logout().then(
                  (value) => context.read<ProfileCubit>().logoutProfile());
            },
          ),
        ],
        child: Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
              width: 2,
            ),
          ),
          width: 101,
          height: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ArDriveIcons.user(size: 14),
              if (walletAddress.isNotEmpty)
                Text(
                  '${walletAddress.substring(0, 2)}...${walletAddress.substring(walletAddress.length - 2)}',
                  style: ArDriveTypography.body
                      .buttonNormalBold()
                      .copyWith(fontWeight: FontWeight.w800),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

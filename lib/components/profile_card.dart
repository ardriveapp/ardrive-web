import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/components/details_panel.dart';
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
        width: 250,
        anchor: const Aligned(
          follower: Alignment.topRight,
          target: Alignment.bottomRight,
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
                      style:
                          ArDriveTypography.body.buttonNormalRegular().copyWith(
                                decoration: TextDecoration.underline,
                              ),
                    ),
                  CopyButton(
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
                    'AR Ballance',
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
                    style: ArDriveTypography.body.buttonNormalRegular(),
                  ),
                  ArDriveIcons.logout(),
                ],
              ),
            ),
            onClick: () => context.read<ProfileCubit>().logoutProfile(),
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
              ArDriveIcons.person(),
              if (walletAddress.isNotEmpty)
                Text(
                  '${walletAddress.substring(0, 2)}...${walletAddress.substring(walletAddress.length - 2)}',
                  style: ArDriveTypography.body.buttonNormalBold(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

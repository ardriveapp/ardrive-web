import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/components/details_panel.dart';
import 'package:ardrive/components/turbo_balance_widget.dart';
import 'package:ardrive/services/turbo/payment_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ProfileCard extends StatefulWidget {
  const ProfileCard({
    super.key,
  });

  @override
  State<ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<ProfileCard> {
  bool _showProfileCard = false;

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
      child: ArDriveOverlay(
        onVisibleChange: (visible) {
          if (!visible) {
            setState(() {
              _showProfileCard = false;
            });
          }
        },
        visible: _showProfileCard,
        anchor: const Aligned(
          follower: Alignment.topRight,
          target: Alignment.bottomRight,
          offset: Offset(0, 4),
        ),
        content: _buildProfileCardContent(context, state, walletAddress),
        child: _buildProfileCardHeader(context, walletAddress),
      ),
    );
  }

  Widget _buildProfileCardContent(
    BuildContext context,
    ProfileLoggedIn state,
    String walletAddress,
  ) {
    return ArDriveCard(
      contentPadding: const EdgeInsets.all(0),
      width: 281,
      boxShadow: BoxShadowCard.shadow60,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          _buildWalletAddressRow(context, state),
          const Divider(
            height: 21,
            indent: 16,
            endIndent: 16,
          ),
          _buildBalanceRow(context, state),
          if (context.read<PaymentService>().useTurboPayment) ...[
            Padding(
              padding: const EdgeInsets.only(top: 20.0),
              child: TurboBalance(
                paymentService: context.read<PaymentService>(),
                wallet: state.wallet,
                onTapAddButton: () {
                  setState(() {
                    _showProfileCard = false;
                  });
                },
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 20.0),
            child: _buildLogoutButton(context),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletAddressRow(BuildContext context, ProfileLoggedIn state) {
    final walletAddress = state.walletAddress;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (walletAddress.isNotEmpty)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      openUrl(
                        url:
                            'https://viewblock.io/arweave/address/$walletAddress',
                      );
                    },
                    child: Text(
                      '${walletAddress.substring(0, 6)}...${walletAddress.substring(walletAddress.length - 5)}',
                      style: ArDriveTypography.body.captionRegular().copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                            decoration: TextDecoration.underline,
                          ),
                    ),
                  ),
                ),
              CopyButton(
                size: 24,
                text: walletAddress,
                showCopyText: false,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceRow(BuildContext context, ProfileLoggedIn state) {
    final walletBalance =
        double.tryParse(utils.winstonToAr(state.walletBalance))
                ?.toStringAsFixed(5) ??
            '0';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appLocalizationsOf(context).arBalance,
            style: ArDriveTypography.body.buttonLargeBold().copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
          ),
          Text(
            '$walletBalance AR',
            style: ArDriveTypography.body.captionRegular().copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeFgSubtle,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return InkWell(
      onTap: () {
        context.read<ArDriveAuth>().logout().then(
              (value) => context.read<ProfileCubit>().logoutProfile(),
            );
      },
      child: Container(
        color: ArDriveTheme.of(context).themeData.colors.themeBgSubtle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24),
          child: Row(
            children: [
              Text(
                appLocalizationsOf(context).logout,
                style:
                    ArDriveTypography.body.captionBold().copyWith(fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCardHeader(BuildContext context, String walletAddress) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _showProfileCard = !_showProfileCard;
        });
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
            ArDriveIcons.user(size: 14),
            if (walletAddress.isNotEmpty)
              Text(
                '${walletAddress.substring(0, 2)}...${walletAddress.substring(walletAddress.length - 2)}',
                style: ArDriveTypography.body.buttonNormalBold().copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
          ],
        ),
      ),
    );
  }
}

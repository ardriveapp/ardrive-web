import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/components/details_panel.dart';
import 'package:ardrive/components/truncated_address.dart';
import 'package:ardrive/entities/address_type.dart';
import 'package:ardrive/entities/profile_source.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/topup/components/turbo_balance_widget.dart';
import 'package:ardrive/user/download_wallet/download_wallet_modal.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url_utils.dart';
import 'package:ardrive/utils/truncate_string.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

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
    return ArDriveClickArea(
      child: ScreenTypeLayout.builder(
        mobile: (context) => _buildLoggedInViewForPlatform(
          context,
          isMobile: true,
        ),
        desktop: (context) => _buildLoggedInViewForPlatform(
          context,
          isMobile: false,
        ),
      ),
    );
  }

  Widget _buildLoggedInViewForPlatform(
    BuildContext context, {
    required bool isMobile,
  }) {
    final state = context.read<ProfileCubit>().state as ProfileLoggedIn;
    final walletAddress = state.walletAddress;

    return ArDriveOverlay(
      onVisibleChange: (visible) {
        if (!visible) {
          setState(() {
            _showProfileCard = false;
          });
        }
      },
      visible: _showProfileCard,
      anchor: Aligned(
        follower: Alignment.topRight,
        target: Alignment.bottomRight,
        offset: isMobile ? const Offset(12, -60) : const Offset(0, 4),
      ),
      content: _buildProfileCardContent(
        context,
        state,
        isMobile: isMobile,
      ),
      child: _buildProfileCardHeader(context, walletAddress),
    );
  }

  Widget _buildProfileCardContent(
    BuildContext context,
    ProfileLoggedIn state, {
    required bool isMobile,
  }) {
    final isEthereum =
        state.profileSource.type == ProfileSourceType.ethereumSignature;

    return ArDriveCard(
      contentPadding: const EdgeInsets.all(0),
      width: 281,
      height: isMobile ? double.infinity : null,
      borderRadius: isMobile ? 0 : null,
      boxShadow: BoxShadowCard.shadow60,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobile)
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ArDriveIconButton(
                    onPressed: () {
                      setState(() {
                        _showProfileCard = false;
                      });
                    },
                    icon: ArDriveIcons.x(
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          if (isEthereum) ...[
            _buildEthereumAddressRow(context, state),
            const SizedBox(height: 8),
            const Divider(
              height: 21,
              indent: 16,
              endIndent: 16,
            ),
          ],
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
            padding: const EdgeInsets.only(top: 20.0, left: 16, right: 16),
            child: ArDriveClickArea(
              child: GestureDetector(
                onTap: () {
                  openFeedbackSurveyUrl();
                },
                child: Text(
                  appLocalizationsOf(context).leaveFeedback,
                  style: ArDriveTypography.body
                      .captionRegular(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeFgSubtle)
                      .copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                        decoration: TextDecoration.underline,
                      ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 20.0),
            child: _buildLogoutButton(context),
          ),
          if (isMobile)
            Expanded(
              child: Container(
                color: ArDriveTheme.of(context).themeData.colors.themeBgSubtle,
              ),
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
        children: [
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    child: Text(
                      // TODO: localize?
                      'AR:',
                      style: ArDriveTypography.body.captionRegular().copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                    ),
                  ),
                  TruncatedAddress(
                    walletAddress: walletAddress,
                    fontSize: 16,
                    color:
                        ArDriveTheme.of(context).themeData.colors.themeFgSubtle,
                    offsetStart: 7,
                    offsetEnd: 7,
                  ),
                ],
              ),
              const Spacer(),
              if (state.wallet is! ArConnectWallet)
                DownloadKeyfileButton(
                  onPressed: () {
                    setState(() {
                      _showProfileCard = false;
                    });
                    showDownloadWalletModal(context);
                  },
                  size: 18,
                ),
              const SizedBox(width: 8),
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

  Widget _buildEthereumAddressRow(BuildContext context, ProfileLoggedIn state) {
    final walletAddess = state.profileSource.address!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    child: Text(
                      'ETH:',
                      style: ArDriveTypography.body.captionRegular().copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                    ),
                  ),
                  TruncatedAddress(
                    walletAddress: walletAddess,
                    fontSize: 16,
                    color:
                        ArDriveTheme.of(context).themeData.colors.themeFgSubtle,
                    offsetStart: 7,
                    offsetEnd: 7,
                    addressType: AddressType.ethereum,
                  ),
                ],
              ),
              const Spacer(),
              CopyButton(
                size: 24,
                text: walletAddess,
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
            style: ArDriveTypography.body
                .captionRegular(
                    color:
                        ArDriveTheme.of(context).themeData.colors.themeFgSubtle)
                .copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return const _LogoutButton();
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
                truncateString(walletAddress, offsetStart: 2, offsetEnd: 2),
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

class _LogoutButton extends StatefulWidget {
  const _LogoutButton();

  @override
  State<_LogoutButton> createState() => __LogoutButtonState();
}

class __LogoutButtonState extends State<_LogoutButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return HoverDetector(
      onExit: () {
        setState(() {
          _isHovering = false;
        });
      },
      onHover: () {
        setState(() {
          _isHovering = true;
        });
      },
      child: InkWell(
        onTap: () {
          context.read<ArDriveAuth>().logout().then(
                (value) => context.read<ProfileCubit>().logoutProfile(),
              );
        },
        child: Container(
          color: _isHovering
              ? ArDriveTheme.of(context).themeData.colors.themeGbMuted
              : ArDriveTheme.of(context).themeData.colors.themeBgSubtle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24),
            child: Row(
              children: [
                Text(
                  appLocalizationsOf(context).logOut,
                  style: ArDriveTypography.body
                      .captionBold()
                      .copyWith(fontSize: 15),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DownloadKeyfileButton extends StatelessWidget {
  final VoidCallback onPressed;
  final double size;
  final double padding;
  final int positionY;
  final int positionX;

  const DownloadKeyfileButton({
    Key? key,
    required this.onPressed,
    this.size = 20,
    this.padding = 4,
    this.positionY = 40,
    this.positionX = 20,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ArDriveIconButton(
      tooltip: appLocalizationsOf(context).downloadWalletKeyfile,
      onPressed: onPressed,
      icon: Padding(
        padding: EdgeInsets.all(padding),
        child: ArDriveIcons.arrowDownload(size: size),
      ),
    );
  }
}

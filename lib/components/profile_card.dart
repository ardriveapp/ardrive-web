import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/components/details_panel.dart';
import 'package:ardrive/components/icon_theme_switcher.dart';
import 'package:ardrive/components/side_bar.dart';
import 'package:ardrive/components/truncated_address.dart';
import 'package:ardrive/gar/presentation/widgets/gar_modal.dart';
import 'package:ardrive/gift/bloc/redeem_gift_bloc.dart';
import 'package:ardrive/gift/redeem_gift_modal.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/topup/components/turbo_balance_widget.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/open_url_utils.dart';
import 'package:ardrive/utils/open_urls.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/truncate_string.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
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
      child: ArDriveButtonNew(
        text: appLocalizationsOf(context).login,
        typography: ArDriveTypographyNew.of(context),
        variant: ButtonVariant.outline,
        maxWidth: 100,
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
        offset: isMobile ? const Offset(12, -60) : const Offset(0, 18),
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
    final typography = ArDriveTypographyNew.of(context);
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
          Container(
            color: ArDriveTheme.of(context).themeData.colorTokens.containerL3,
            child: Column(
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
                _buildWalletAddressRow(context, state),
                if (state.wallet is! ArConnectWallet) ...[
                  const SizedBox(height: 8),
                ],
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
                const SizedBox(height: 20),
              ],
            ),
          ),
          ArDriveAccordion(
            backgroundColor: Colors.transparent,
            children: [
              ArDriveAccordionItem(
                Text(
                  'Gift',
                  style: typography.paragraphNormal(
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
                [
                  _ProfileMenuAccordionItem(
                    text: 'Gift',
                    onTap: () {
                      openUrl(url: Resources.sendGiftLink);
                    },
                  ),
                  _ProfileMenuAccordionItem(
                    text: 'Reedem Gift',
                    onTap: () {
                      showArDriveDialog(
                        context,
                        content: BlocProvider(
                          create: (context) => RedeemGiftBloc(
                              paymentService: context.read<PaymentService>(),
                              auth: context.read<ArDriveAuth>()),
                          child: const RedeemGiftModal(),
                        ),
                      );
                    },
                  ),
                ],
              ),
              ArDriveAccordionItem(
                Text(
                  'Support',
                  style: typography.paragraphNormal(
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
                [
                  _ProfileMenuAccordionItem(
                    text: 'Docs',
                    onTap: () {
                      openDocs();
                    },
                  ),
                  _ProfileMenuAccordionItem(
                    text: 'Help',
                    onTap: () {
                      openHelp();
                    },
                  ),
                  _ProfileMenuAccordionItem(
                    text: 'Leave Feedback',
                    onTap: () {
                      openFeedbackSurveyUrl();
                    },
                  ),
                  _ProfileMenuAccordionItem(
                    text: 'Share Logs',
                    onTap: () {
                      shareLogs(
                        context: context,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: 8),
          ArDriveAccordion(backgroundColor: Colors.transparent, children: [
            // gateway switcher
            ArDriveAccordionItem(
              Text(
                'Advanced',
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.semiBold,
                ),
              ),
              [
                _ProfileMenuAccordionItem(
                  text: 'Switch Gateway',
                  onTap: () {
                    showGatewaySwitcherModal(context);
                  },
                ),
              ],
            ),
          ]),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Theme',
                  style: typography.paragraphNormal(
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
                IconThemeSwitcher(
                  color:
                      ArDriveTheme.of(context).themeData.colorTokens.iconHigh,
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 20.0),
            child: _LogoutButton(),
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
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              if (walletAddress.isNotEmpty)
                TruncatedAddress(
                  walletAddress: walletAddress,
                  fontSize: 18,
                ),
              const Spacer(),
              ArDriveIconButton(
                icon: ArDriveIcons.download(
                    color: colorTokens.textHigh, size: 21),
              ),
              CopyButton(
                size: 21,
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
    final walletBalance = convertWinstonToLiteralString(state.walletBalance);
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appLocalizationsOf(context).arBalance,
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.semiBold,
              color: colorTokens.textHigh,
            ),
          ),
          Text(
            '$walletBalance AR',
            style: typography.paragraphNormal(
              color: colorTokens.textLow,
              fontWeight: ArFontWeight.semiBold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCardHeader(BuildContext context, String walletAddress) {
    final typography = ArDriveTypographyNew.of(context);
    return ArDriveButtonNew(
      text: truncateString(walletAddress, offsetStart: 2, offsetEnd: 2),
      typography: typography,
      variant: ButtonVariant.outline,
      maxWidth: 100,
      onPressed: () {
        setState(() {
          _showProfileCard = !_showProfileCard;
        });
      },
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
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
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
          final arDriveAuth = context.read<ArDriveAuth>();
          final profileCubit = context.read<ProfileCubit>();

          arDriveAuth.logout().then(
            (value) {
              profileCubit.logoutProfile();
              PlausibleEventTracker.trackPageview(
                  page: PlausiblePageView.logout);
            },
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
                  style: typography.paragraphNormal(
                    color: colorTokens.textHigh,
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
                const Spacer(),
                ArDriveIcons.logout(size: 21),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileMenuAccordionItem extends StatelessWidget {
  const _ProfileMenuAccordionItem({
    required this.text,
    required this.onTap,
  });

  final String text;
  final Function() onTap;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);

    return ArDriveClickArea(
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: 30.0, right: 15),
          child: Text(
            text,
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.semiBold,
            ),
          ),
        ),
      ),
    );
  }
}

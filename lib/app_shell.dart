import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_bloc.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_event.dart';
import 'package:ardrive/components/migrate_private_drives_modal.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/components/side_bar.dart';
import 'package:ardrive/components/sync_failure_test_panel.dart';
import 'package:ardrive/components/topbar/help_button.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/shared/blocs/banner/app_banner_bloc.dart';
import 'package:ardrive/shared/blocs/private_drive_migration/private_drive_migration_bloc.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/presentation/sync_overlay.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/size_constants.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

import 'blocs/blocs.dart';
import 'components/app_top_bar.dart';
import 'components/banners/app_announcement_banner.dart';
import 'components/wallet_switch_dialog.dart';

class AppShell extends StatefulWidget {
  final Widget page;

  const AppShell({
    super.key,
    required this.page,
  });

  @override
  AppShellState createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  bool _showProfileOverlay = false;
  bool _showWalletSwitchDialog = true;

  @override
  void initState() {
    onArConnectWalletSwitch(() {
      logger.d('Wallet switch detected');
      context.read<ProfileCubit>().isCurrentProfileArConnect().then(
        (isCurrentProfileArConnect) {
          if (_showWalletSwitchDialog) {
            if (isCurrentProfileArConnect) {
              context.read<ArDriveAuth>().isUserLoggedIn().then((isLoggedIn) {
                context.read<ProfileCubit>().logoutIfWalletMismatch();
                if (isLoggedIn) {
                  logger.d('Wallet switch detected while logged in'
                      ' to ArConnect. Showing wallet switch dialog.');
                  showArDriveDialog(
                    context,
                    content: const WalletSwitchDialog(),
                  );
                }
              });
            } else {
              logger.d('Wallet switch detected while not logged in'
                  ' to ArConnect. Ignoring.');
            }
          }
          // Used to prevent the dialog being shown multiple times.
          _showWalletSwitchDialog = false;
        },
      );
    });

    super.initState();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<DrivesCubit, DrivesState>(
        builder: (context, drivesState) {
          // The page, and nothing wrapped around it for the sake of a sync.
          //
          // A banner above every screen used to live here. It reported the
          // running sync in full, permanently, to everyone - which is level-2
          // detail forced on a user who has not asked a question. What a sync
          // is doing is one tap away instead, on the top bar's indicator, and
          // the record of what it did is one more tap after that. In a working
          // app there is nothing to read, so there is nothing on screen.
          final page = widget.page;

          Widget buildPage(scaffold) => Material(
                child: BlocConsumer<SyncCubit, SyncState>(
                  listener: (context, syncState) async {
                    if (drivesState is DrivesLoadSuccess) {
                      if (syncState is! SyncInProgress) {
                        final promptToSnapshotBloc =
                            context.read<PromptToSnapshotBloc>();

                        promptToSnapshotBloc.add(SelectedDrive(
                          driveId: drivesState.selectedDriveId,
                        ));
                      }
                    }
                  },
                  builder: (context, syncState) {
                    return Stack(children: [
                      scaffold,
                      SyncOverlay(syncState: syncState),
                      // Add the sync failure test panel (only visible in debug mode)
                      if (kDebugMode) const SyncFailureTestPanel(),
                    ]);
                  },
                ),
              );
          return ScreenTypeLayout.builder(
            desktop: (context) {
              return buildPage(
                BlocBuilder<PrivateDriveMigrationBloc,
                    PrivateDriveMigrationState>(
                  builder: (context, state) {
                    return Column(
                      children: [
                        _buildAnnouncementBanner(
                          context,
                          message: '', // Configure message when enabling banner
                        ),
                        if (state is! PrivateDriveMigrationHidden)
                          _updatePrivateDrivesBanner(context, true),
                        Flexible(
                          child: Row(
                            children: [
                              const AppSideBar(),
                              Container(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .backgroundColor,
                                width: 16,
                              ),
                              Expanded(
                                child: Scaffold(
                                  backgroundColor: ArDriveTheme.of(context)
                                      .themeData
                                      .backgroundColor,
                                  body: page,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );
            },
            mobile: (context) => buildPage(
              BlocBuilder<PrivateDriveMigrationBloc,
                  PrivateDriveMigrationState>(
                builder: (context, state) {
                  return Column(
                    children: [
                      _buildAnnouncementBanner(
                        context,
                        message: '', // Configure message when enabling banner
                      ),
                      if (state is! PrivateDriveMigrationHidden)
                        _updatePrivateDrivesBanner(context, false),
                      Flexible(
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .backgroundColor,
                                child: page,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      );

  Widget _buildAnnouncementBanner(
    BuildContext context, {
    required String message,
    String? url,
    String? urlText,
  }) {
    // Don't render banner if no message is configured
    if (message.isEmpty) {
      return const SizedBox.shrink();
    }

    return BlocBuilder<AppBannerBloc, AppBannerState>(
      builder: (context, state) {
        if (state is AppBannerVisible &&
            state.banner == AppBannerType.announcement) {
          return AppAnnouncementBanner(
            message: message,
            url: url,
            urlText: urlText,
            onDismiss: () => context.read<AppBannerBloc>().add(
                  const AppBannerDismissed(
                    banner: AppBannerType.announcement,
                  ),
                ),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _updatePrivateDrivesBanner(BuildContext context, bool isDesktop) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      height: 45,
      width: double.maxFinite,
      color: colorTokens.buttonPrimaryDefault,
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          ArDriveIcons.privateDrive(
            color: colorTokens.textOnPrimary,
            size: 18,
          ),
          const SizedBox(width: 8),
          // move two pixels above
          Transform(
            transform: Matrix4.translationValues(0.0, -2.0, 0.0),
            child: isDesktop
                ? RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text:
                              'Please update your private drives to continue using them in the future: ',
                          style: typography.paragraphNormal(
                              fontWeight: ArFontWeight.semiBold,
                              color: colorTokens.textOnPrimary),
                        ),
                        TextSpan(
                          text: 'Update Now!',
                          recognizer: TapGestureRecognizer()
                            ..onTap = () {
                              showMigratePrivateDrivesModal(context);
                            },
                          style: typography
                              .paragraphNormal(
                                  fontWeight: ArFontWeight.semiBold,
                                  color: colorTokens.textOnPrimary)
                              .copyWith(
                                decoration: TextDecoration.underline,
                              ),
                        ),
                      ],
                    ),
                  )
                : GestureDetector(
                    onTap: () => showMigratePrivateDrivesModal(context),
                    child: Text(
                      'Please update your Private Drives',
                      style: typography
                          .paragraphNormal(
                            color: colorTokens.textOnPrimary,
                            fontWeight: ArFontWeight.semiBold,
                          )
                          .copyWith(decoration: TextDecoration.underline),
                    ),
                  ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  void toggleProfileOverlay() =>
      setState(() => _showProfileOverlay = !_showProfileOverlay);
}

/// The bar's own row, which is all of it.
const double _mobileAppBarRowHeight = 80;

// TODO: add the gift icon
class MobileAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MobileAppBar({
    super.key,
    this.leading,
    this.showDrawerButton = true,
  });

  final Widget? leading;
  final bool showDrawerButton;

  @override
  // Its own row and nothing else. Nothing about a sync is laid out here: a
  // `Scaffold` sizes its app bar to a `preferredSize` a const widget cannot
  // change, so anything that came and went with a sync could only live in this
  // bar as a permanently reserved slot - an empty band on every screen for the
  // whole of the time no sync is running, which is nearly all of it. The
  // indicator in the row reports a sync in the space it already occupies.
  Size get preferredSize => const Size.fromHeight(_mobileAppBarRowHeight);

  @override
  Widget build(BuildContext context) {
    final isLightMode = ArDriveTheme.of(context).themeData.name == 'light';
    return SafeArea(
      child: Container(
        color: ArDriveTheme.of(context).themeData.tableTheme.cellColor,
        child: SizedBox(
          height: _mobileAppBarRowHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 7.0),
                child: leading ??
                    (showDrawerButton
                        ? ArDriveIconButton(
                            icon: ArDriveIcons.menu(
                              size: defaultIconSize,
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeFgDefault,
                            ),
                            onPressed: () => Scaffold.of(context).openDrawer(),
                          )
                        : Container()),
              ),
              if (!showDrawerButton)
                Padding(
                  padding: const EdgeInsets.only(
                    left: 24.0,
                  ),
                  child: ArDriveImage(
                    image: AssetImage(
                      isLightMode
                          ? Resources.images.brand.blackLogo1
                          : Resources.images.brand.whiteLogo1,
                    ),
                    width: 128,
                    height: 28,
                  ),
                ),
              const Spacer(),
              const GlobalHideToggleButton(),
              const SizedBox(width: 8),
              const SyncButton(),
              const SizedBox(width: 8),
              const HelpButtonTopBar(),
              const SizedBox(
                width: 24,
              ),
              const Padding(
                padding: EdgeInsets.only(right: 12.0),
                child: ProfileCard(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

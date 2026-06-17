import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/components/copy_button.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/components/graphql_endpoint_dialog.dart';
import 'package:ardrive/components/icon_theme_switcher.dart';
import 'package:ardrive/components/wallet_gradient_avatar.dart';
import 'package:ardrive/components/truncated_address.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/gar/domain/repositories/gar_repository.dart';
import 'package:ardrive/gar/presentation/widgets/gateway_input_modal.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/components/help_info_modals.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/turbo/topup/blocs/turbo_balance/turbo_balance_cubit.dart';
import 'package:ardrive/turbo/topup/views/topup_modal.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/user/balance/user_balance_bloc.dart';
import 'package:ardrive/user/download_wallet/download_wallet_modal.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/truncate_string.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart';
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
  Future<_AccountStats>? _accountStatsFuture;

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
      tooltip: appLocalizationsOf(context).userProfile,
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
    final walletAddress = state.user.displayAddress;

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
        target: isMobile ? Alignment.bottomRight : Alignment.topRight,
        offset: isMobile ? const Offset(12, -60) : const Offset(0, 0),
      ),
      content: _buildProfileCardContent(
        context,
        state,
        isMobile: isMobile,
      ),
      child: _buildProfileCardHeader(context, walletAddress, state.user),
    );
  }

  Widget _buildProfileCardContent(
    BuildContext context,
    ProfileLoggedIn state, {
    required bool isMobile,
  }) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return ArDriveCard(
      contentPadding: const EdgeInsets.all(0),
      width: 281,
      height: isMobile ? double.infinity : null,
      borderRadius: isMobile ? 0 : null,
      boxShadow: BoxShadowCard.shadow80,
      content: Container(
        color: ArDriveTheme.of(context).themeData.dropdownTheme.backgroundColor,
        child: Column(
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
            _buildIdentityHeader(context, state),
            _buildAccountStats(context),
            const Divider(height: 1, indent: 16, endIndent: 16),
            _buildBalanceSection(context, state),
            const SizedBox(height: 8),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ArDriveAccordion(
              backgroundColor: Colors.transparent,
              automaticallyCloseWhenOpenAnotherItem: true,
              children: [
                ArDriveAccordionItem(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state.user.sourceWalletAddress != null
                            ? 'Wallets'
                            : 'Wallet',
                        style: typography.paragraphNormal(
                          fontWeight: ArFontWeight.semiBold,
                        ),
                      ),
                      if (state.user.sourceWalletAddress != null) ...[
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _showProfileCard = false;
                            });
                            showArDriveDialog(
                              context,
                              content: ArDriveStandardModalNew(
                                hasCloseButton: true,
                                title: 'About Your Wallets',
                                description:
                                    'Your ${state.user.sourceWalletAddress!.startsWith('0x') ? 'Ethereum' : 'Solana'} wallet is used to sign in. '
                                    'A unique Arweave wallet is automatically derived from it to store your data permanently on the Arweave network.\n\n'
                                    'Your Arweave wallet is deterministic — it will always be the same when you sign in with the same ${state.user.sourceWalletAddress!.startsWith('0x') ? 'Ethereum' : 'Solana'} wallet.\n\n'
                                    'Never share your wallet private keys with anyone.',
                              ),
                            );
                          },
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Icon(
                              Icons.info_outline,
                              size: 14,
                              color: colorTokens.textLow,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  _buildWalletSettingsItems(context, state),
                ),
                ArDriveAccordionItem(
                  Text(
                    'Settings',
                    style: typography.paragraphNormal(
                      fontWeight: ArFontWeight.semiBold,
                    ),
                  ),
                  [
                    const SizedBox(height: 8),
                    _ProfileMenuAccordionItem(
                      text: 'Switch Gateway',
                      onTap: () {
                        setState(() {
                          _showProfileCard = false;
                        });
                        _showGatewayInputDialog(
                          context,
                          onSave: (newGatewayUrl) async {
                            final cs = context.read<ConfigService>();
                            final garRepository = GarRepositoryImpl(
                              configService: cs,
                              arweave: context.read<ArweaveService>(),
                              arioSDK: ArioSDKFactory().create(),
                              http: ArDriveHTTP(),
                            );
                            await garRepository
                                .updateCustomGateway(newGatewayUrl);
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    _ProfileMenuAccordionItem(
                      text: 'Switch GraphQL Server',
                      onTap: () {
                        setState(() {
                          _showProfileCard = false;
                        });
                        _showGQLServerDialog(context);
                      },
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ArDriveToggleSwitch(
                        alignRight: true,
                        value: context.read<ConfigService>().config.autoSync,
                        text: 'Automatic Sync',
                        textStyle: typography.paragraphNormal(
                          fontWeight: ArFontWeight.semiBold,
                          color: colorTokens.textMid,
                        ),
                        onChanged: (value) {
                          final config = context.read<ConfigService>().config;
                          context.read<ConfigService>().updateAppConfig(
                                config.copyWith(autoSync: value),
                              );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: StreamBuilder<UserPreferences>(
                        stream: context
                            .read<UserPreferencesRepository>()
                            .watch(),
                        builder: (context, snapshot) {
                          final repo =
                              context.read<UserPreferencesRepository>();
                          final syncAllDrivesOnLogin =
                              snapshot.data?.syncAllDrivesOnLogin ??
                                  repo.currentPreferences
                                      ?.syncAllDrivesOnLogin ??
                                  true;
                          return ArDriveToggleSwitch(
                            alignRight: true,
                            value: syncAllDrivesOnLogin,
                            text: appLocalizationsOf(context)
                                .syncAllDrivesOnLogin,
                            textStyle: typography.paragraphNormal(
                              fontWeight: ArFontWeight.semiBold,
                              color: colorTokens.textMid,
                            ),
                            onChanged: (value) {
                              context
                                  .read<UserPreferencesRepository>()
                                  .saveSyncAllDrivesOnLogin(value);
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ArDriveToggleSwitch(
                        alignRight: true,
                        value: context
                            .read<ConfigService>()
                            .config
                            .uploadThumbnails,
                        text: 'Upload with thumbnails',
                        textStyle: typography.paragraphNormal(
                          fontWeight: ArFontWeight.semiBold,
                          color: colorTokens.textMid,
                        ),
                        onChanged: (value) {
                          final config = context.read<ConfigService>().config;
                          context.read<ConfigService>().updateAppConfig(
                                config.copyWith(uploadThumbnails: value),
                              );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ArDriveToggleSwitch(
                        alignRight: true,
                        value: context
                            .read<ConfigService>()
                            .config
                            .enableSyncFromSnapshot,
                        text: 'Sync From Snapshots',
                        textStyle: typography.paragraphNormal(
                          fontWeight: ArFontWeight.semiBold,
                          color: colorTokens.textMid,
                        ),
                        onChanged: (value) {
                          final config = context.read<ConfigService>().config;
                          context.read<ConfigService>().updateAppConfig(
                                config.copyWith(enableSyncFromSnapshot: value),
                              );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Theme',
                            style: typography.paragraphNormal(
                              fontWeight: ArFontWeight.semiBold,
                              color: colorTokens.textMid,
                            ),
                          ),
                          IconThemeSwitcher(
                            color: colorTokens.iconHigh,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ],
            ),
          // Logout — always at the very bottom
          const Divider(height: 1, indent: 16, endIndent: 16),
          _LogoutButton(
            onLogout: () {
              _showProfileCard = false;
              setState(() {});
            },
          ),
          if (isMobile)
            Expanded(
              child: Container(
                color: ArDriveTheme.of(context).themeData.dropdownTheme.backgroundColor,
              ),
            ),
        ],
      ),
      ),
    );
  }

  Widget _buildAccountStats(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final driveDao = context.read<DriveDao>();
    _accountStatsFuture ??= _getAccountStats(driveDao);

    return FutureBuilder<_AccountStats>(
      future: _accountStatsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final stats = snapshot.data!;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Center(
            child: Text(
              '${stats.driveCount} ${stats.driveCount == 1 ? 'drive' : 'drives'} · ${stats.fileCount} ${stats.fileCount == 1 ? 'file' : 'files'} · ${_formatBytes(stats.totalSize)}',
              style: typography.caption(
                color: colorTokens.textLow,
                fontWeight: ArFontWeight.book,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<_AccountStats> _getAccountStats(DriveDao driveDao) async {
    final drives = await driveDao.allDrives().get();
    var fileCount = 0;
    var totalSize = 0;
    for (final drive in drives) {
      final files =
          await driveDao.filesInDriveWithRevisionTransactions(driveId: drive.id).get();
      fileCount += files.length;
      for (final file in files) {
        totalSize += file.size;
      }
    }
    return _AccountStats(
      driveCount: drives.length,
      fileCount: fileCount,
      totalSize: totalSize,
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Widget _buildIdentityHeader(BuildContext context, ProfileLoggedIn state) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Center(
            child: WalletGradientAvatar(
              address: state.user.displayAddress,
              size: 48,
              ringColor: getWalletIndicatorColor(state.user),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: BlocBuilder<ProfileNameBloc, ProfileNameState>(
              builder: (context, nameState) {
                final name = nameState is ProfileNameLoaded
                    ? nameState.primaryNameDetails.primaryName
                    : truncateString(state.user.displayAddress,
                        offsetStart: 6, offsetEnd: 4);
                return Text(
                  name,
                  style: typography.paragraphLarge(
                    fontWeight: ArFontWeight.bold,
                    color: colorTokens.textHigh,
                  ),
                  overflow: TextOverflow.ellipsis,
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  /// Builds wallet address rows for the Settings accordion.
  List<Widget> _buildWalletSettingsItems(
      BuildContext context, ProfileLoggedIn state) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final sourceAddress = state.user.sourceWalletAddress;
    final arweaveAddress = state.user.walletAddress;

    return [
      const SizedBox(height: 8),
      if (sourceAddress != null) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _WalletAddressLine(
            label: sourceAddress.startsWith('0x') ? 'ETH' : 'SOL',
            address: sourceAddress,
            explorerUrl: sourceAddress.startsWith('0x')
                ? 'https://etherscan.io/address/$sourceAddress'
                : 'https://solscan.io/account/$sourceAddress',
          ),
        ),
        const SizedBox(height: 4),
      ],
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _WalletAddressLine(
          label: 'AR',
          address: arweaveAddress,
          explorerUrl:
              'https://viewblock.io/arweave/address/$arweaveAddress',
        ),
      ),
      if (state.user.profileType != ProfileType.arConnect &&
          state.user.sourceWalletAddress == null) ...[
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => showDownloadWalletModal(context),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Text(
                  'Download wallet backup',
                  style: typography.paragraphSmall(
                    color: colorTokens.textLow,
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ];
  }

  Widget _buildBalanceSection(BuildContext context, ProfileLoggedIn state) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final walletBalance = state.user.walletBalance;
    final hasArBalance = walletBalance > BigInt.zero;

    return BlocProvider(
      create: (context) => TurboBalanceCubit(
        paymentService: context.read<PaymentService>(),
        wallet: state.user.wallet,
      )..getBalance(),
      child: BlocBuilder<TurboBalanceCubit, TurboBalanceState>(
        builder: (context, turboState) {
          final creditsText = turboState is TurboBalanceSuccessState
              ? convertWinstonToLiteralString(turboState.balance)
              : turboState is TurboBalanceLoading
                  ? '...'
                  : '0.0000';

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                // Credits row — always visible
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Credits',
                          style: typography.paragraphNormal(
                            fontWeight: ArFontWeight.semiBold,
                            color: colorTokens.textMid,
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _showProfileCard = false;
                            });
                            showTurboInfoModal(context: context);
                          },
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Icon(
                              Icons.info_outline,
                              size: 14,
                              color: colorTokens.textLow,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          creditsText,
                          style: typography.paragraphNormal(
                            color: colorTokens.textHigh,
                            fontWeight: ArFontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _showProfileCard = false;
                            });
                            showTurboTopupModal(context);
                          },
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colorTokens.textMid,
                                  width: 1,
                                ),
                              ),
                              child: Icon(
                                Icons.add,
                                size: 12,
                                color: colorTokens.textMid,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                // AR Balance — only if non-zero
                if (hasArBalance) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'AR Balance',
                        style: typography.paragraphNormal(
                          fontWeight: ArFontWeight.semiBold,
                          color: colorTokens.textMid,
                        ),
                      ),
                      Text(
                        convertWinstonToLiteralString(walletBalance),
                        style: typography.paragraphNormal(
                          color: colorTokens.textHigh,
                          fontWeight: ArFontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  // ignore: unused_element
  Widget _buildIOTokenRow(BuildContext context, ProfileLoggedIn state) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    final ioTokens = state.user.ioTokens;

    return BlocProvider(
      create: (context) => UserBalanceBloc(auth: context.read<ArDriveAuth>())
        ..add(GetUserBalance()),
      child: BlocBuilder<UserBalanceBloc, UserBalanceState>(
        builder: (context, state) {
          if (state is UserBalanceLoaded) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ARIO Tokens',
                    style: typography.paragraphNormal(
                      fontWeight: ArFontWeight.semiBold,
                      color: colorTokens.textHigh,
                    ),
                  ),
                  if (state is UserBalanceLoadingIOTokens &&
                      !state.errorFetchingIOTokens)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(),
                    ),
                  if (ioTokens != null)
                    Text(
                      ioTokens,
                      style: typography.paragraphNormal(
                        color: colorTokens.textLow,
                        fontWeight: ArFontWeight.semiBold,
                      ),
                    ),
                  if (state.errorFetchingIOTokens) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Error fetching ARIO balance',
                          style: typography.paragraphNormal(
                            fontWeight: ArFontWeight.semiBold,
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeErrorDefault,
                          ),
                        ),
                        ArDriveIconButton(
                          icon: ArDriveIcons.refresh(),
                          onPressed: () {
                            context
                                .read<UserBalanceBloc>()
                                .add(RefreshUserBalance());
                          },
                        )
                      ],
                    ),
                  ]
                ],
              ),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  void _showGatewayInputDialog(BuildContext context,
      {required Function(String) onSave}) {
    final configService = context.read<ConfigService>();
    final currentGateway =
        configService.config.arweaveGatewayForDataRequest.url;

    showGatewayInputModal(
      context,
      initialGateway: currentGateway,
      onSave: onSave,
    );
  }

  Future<void> _showGQLServerDialog(BuildContext context) async {
    await showAnimatedDialogWithBuilder(
      context,
      builder: (context) => GraphQLEndpointDialog(
        initialEndpoint:
            context.read<ConfigService>().config.arweaveGatewayUrl ??
                defaultGraphqlGateway,
        onSave: (newEndpoint) {
          const graphqlSuffix = '/graphql';
          final normalizedEndpoint = newEndpoint.endsWith(graphqlSuffix)
              ? newEndpoint.substring(
                  0, newEndpoint.length - graphqlSuffix.length)
              : newEndpoint;
          final configService = context.read<ConfigService>();
          configService.updateAppConfig(
            configService.config.copyWith(
              arweaveGatewayUrl: normalizedEndpoint,
            ),
          );
          context
              .read<ArweaveService>()
              .updateGraphQLEndpoint(normalizedEndpoint);
        },
      ),
    );
  }

  Widget _buildProfileCardHeader(
      BuildContext context, String walletAddress, User user) {
    return ProfileCardHeader(
      walletAddress: walletAddress,
      walletIndicatorColor: getWalletIndicatorColor(user),
      onPressed: () {
        setState(() {
          _showProfileCard = !_showProfileCard;
        });
      },
    );
  }
}

class _LogoutButton extends StatefulWidget {
  const _LogoutButton({
    required this.onLogout,
  });

  final Function onLogout;

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

          widget.onLogout();

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
              : Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14),
            child: Row(
              children: [
                Text(
                  appLocalizationsOf(context).logOut,
                  style: typography.paragraphNormal(
                    color: colorTokens.textMid,
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
    final colors = ArDriveTheme.of(context).themeData.colorTokens;

    return ArDriveClickArea(
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            text,
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.semiBold,
              color: colors.textMid,
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileCardHeader extends StatelessWidget {
  final String walletAddress;
  final VoidCallback onPressed;
  final bool isExpanded;
  final bool hasLogoutButton;
  final Function()? onClickLogout;
  final String? logoutTooltip;

  /// Colored indicator dot for wallet type.
  final Color? walletIndicatorColor;

  const ProfileCardHeader({
    super.key,
    required this.walletAddress,
    required this.onPressed,
    this.isExpanded = false,
    this.hasLogoutButton = false,
    this.onClickLogout,
    this.logoutTooltip,
    this.walletIndicatorColor,
  });

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);

    return BlocBuilder<ProfileNameBloc, ProfileNameState>(
      builder: (context, state) {
        if (state.walletAddress == null || state.walletAddress!.isEmpty) {
          return const SizedBox.shrink();
        }

        final primaryName = _getPrimaryName(state, walletAddress);
        final maxWidth = _calculateMaxWidth(primaryName, state);
        final truncatedWalletAddress = getTruncatedWalletAddress(
            primaryName, walletAddress,
            isExpanded: isExpanded);
        final tooltipMessage = primaryName.length > 20 ? primaryName : null;
        return ArDriveTooltip(
          message: tooltipMessage ?? '',
          child: ArDriveButtonNew(
            text: primaryName,
            typography: typography,
            variant: ButtonVariant.outline,
            content: _buildLoadedContent(
                context, state, primaryName, truncatedWalletAddress, maxWidth),
            maxWidth: maxWidth,
            maxHeight: state is ProfileNameLoaded ? 60 : 46,
            onPressed: onPressed,
          ),
        );
      },
    );
  }

  String _getPrimaryName(ProfileNameState state, String walletAddress) {
    if (state is ProfileNameLoaded) {
      return state.primaryNameDetails.primaryName;
    }

    return truncateString(walletAddress, offsetStart: 6, offsetEnd: 4);
  }

  double _calculateMaxWidth(String primaryName, ProfileNameState state) {
    if (state is! ProfileNameLoaded && !isExpanded) {
      return 180;
    }

    double width = primaryName.length * 20;

    return width.clamp(110, 230);
  }

  Widget? _buildProfileIcon(ProfileNameLoaded state) {
    if (state.primaryNameDetails.logo == null) {
      return null;
    }

    final logoUrl = state.primaryNameDetails.logo!.startsWith('http')
        ? state.primaryNameDetails.logo!
        : 'https://turbo-gateway.com/${state.primaryNameDetails.logo}';

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ClipOval(
        child: ArDriveImage(
          image: NetworkImage(logoUrl),
          width: 34,
          height: 34,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _buildLoadedContent(
    BuildContext context,
    ProfileNameState state,
    String primaryName,
    String truncatedWalletAddress,
    double maxWidth,
  ) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    if (state is! ProfileNameLoaded) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(left: 8.0, right: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6.0),
                child: WalletGradientAvatar(
                  address: walletAddress,
                  size: 28,
                  ringColor: walletIndicatorColor,
                ),
              ),
              Flexible(
                child: Text(
                  isExpanded ? walletAddress : truncatedWalletAddress,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: typography.paragraphNormal(
                    fontWeight: ArFontWeight.semiBold,
                    color:
                        isExpanded ? colorTokens.textLow : colorTokens.textHigh,
                  ),
                ),
              ),
              if (hasLogoutButton)
                Padding(
                  padding: const EdgeInsets.only(left: 16.0),
                  child: GestureDetector(
                    onTap: onClickLogout,
                    child: ArDriveClickArea(
                      tooltip: logoutTooltip,
                      child: ArDriveIcons.closeCircle(
                        size: 21,
                        color: colorTokens.iconLow,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final icon = _buildProfileIcon(state);

    return ConstrainedBox(
      constraints: isExpanded
          ? const BoxConstraints(maxWidth: double.infinity)
          : BoxConstraints(maxWidth: maxWidth),
      child: Row(
        mainAxisAlignment: isExpanded
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.spaceEvenly,
        mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null)
                  icon
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: WalletGradientAvatar(
                      address: walletAddress,
                      size: 34,
                      ringColor: walletIndicatorColor,
                    ),
                  ),
                Flexible(
                  child: SizedBox(
                    height: 46,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: Text(
                            primaryName,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: typography.paragraphLarge(
                              fontWeight: ArFontWeight.semiBold,
                              color: colorTokens.textHigh,
                            ),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            isExpanded
                                ? walletAddress
                                : truncatedWalletAddress,
                            overflow: TextOverflow.ellipsis,
                            softWrap: true,
                            maxLines: 1,
                            style: typography.paragraphSmall(
                              fontWeight: ArFontWeight.book,
                              color: colorTokens.textLow,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (hasLogoutButton)
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: GestureDetector(
                onTap: onClickLogout,
                child: ArDriveClickArea(
                  tooltip: logoutTooltip,
                  child: ArDriveIcons.closeCircle(
                    size: 21,
                    color: colorTokens.iconLow,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String getTruncatedWalletAddress(
  String primaryName,
  String walletAddress, {
  bool isExpanded = false,
}) {
  if (primaryName.length > 20 || isExpanded) {
    // replace the hyphen with a unicode minus to avoid truncation in the middle of the text
    return truncateString(walletAddress.replaceAll('-', '−'),
        offsetStart: 12, offsetEnd: 12);
  }

  var offsetStart = primaryName.length ~/ 2;
  var offsetEnd = primaryName.length ~/ 2;

  if (offsetStart < 6) {
    offsetStart = 3;
  }

  if (offsetEnd < 6) {
    offsetEnd = 3;
  }

  return truncateString(
    walletAddress,
    offsetStart: offsetStart,
    offsetEnd: offsetEnd,
  );
}

class _ArweaveWalletDisclosure extends StatefulWidget {
  final String arweaveAddress;
  final bool isEthereum;

  const _ArweaveWalletDisclosure({
    required this.arweaveAddress,
    required this.isEthereum,
  });

  @override
  State<_ArweaveWalletDisclosure> createState() =>
      _ArweaveWalletDisclosureState();
}

class _ArweaveWalletDisclosureState extends State<_ArweaveWalletDisclosure> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final chainName = widget.isEthereum ? 'Ethereum' : 'Solana';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(
                      _expanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      size: 16,
                      color: colorTokens.textLow,
                    ),
                  ),
                ),
                Text(
                  'Arweave wallet',
                  style: typography.paragraphSmall(
                    color: colorTokens.textLow,
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 6),
            child: Text(
              'Your $chainName wallet derives a unique Arweave '
              'wallet used to store your data permanently.',
              style: typography.caption(
                color: colorTokens.textLow,
                fontWeight: ArFontWeight.book,
              ),
            ),
          ),
          _WalletAddressLine(
            label: 'AR',
            address: widget.arweaveAddress,
            explorerUrl:
                'https://viewblock.io/arweave/address/${widget.arweaveAddress}',
          ),
        ],
      ],
    );
  }
}

class _WalletAddressLine extends StatelessWidget {
  final String label;
  final String address;
  final String explorerUrl;

  const _WalletAddressLine({
    required this.label,
    required this.address,
    required this.explorerUrl,
  });

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(
            label,
            style: typography.paragraphSmall(
              color: colorTokens.textLow,
              fontWeight: ArFontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: TruncatedAddress(
            walletAddress: address,
            explorerUrl: explorerUrl,
          ),
        ),
        CopyButton(
          size: 18,
          text: address,
          showCopyText: false,
        ),
      ],
    );
  }
}

/// Returns the wallet indicator color based on the user's profile.
/// Purple for Solana, blue for Ethereum, white for Arweave.
Color getWalletIndicatorColor(User user) {
  final source = user.sourceWalletAddress;
  if (source != null) {
    if (source.startsWith('0x')) {
      // Ethereum-derived wallet
      return const Color(0xFF627EEA);
    }
    // Solana-derived wallet
    return const Color(0xFF9945FF);
  }
  // Arweave (ArConnect, JSON file)
  return const Color(0xFFFFFFFF);
}

class _AccountStats {
  final int driveCount;
  final int fileCount;
  final int totalSize;

  _AccountStats({
    required this.driveCount,
    required this.fileCount,
    required this.totalSize,
  });
}

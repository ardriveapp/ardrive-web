import 'dart:async';
import 'dart:convert';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/components/copy_button.dart';
import 'package:ardrive/components/icon_theme_switcher.dart';
import 'package:ardrive/components/side_bar.dart';
import 'package:ardrive/components/truncated_address.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/gar/presentation/widgets/gar_modal.dart';
import 'package:ardrive/gift/bloc/redeem_gift_bloc.dart';
import 'package:ardrive/gift/redeem_gift_modal.dart';
import 'package:ardrive/main.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/topup/components/turbo_balance_widget.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/user/balance/user_balance_bloc.dart';
import 'package:ardrive/user/download_wallet/download_wallet_modal.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/open_url_utils.dart';
import 'package:ardrive/utils/open_urls.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/truncate_string.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:responsive_builder/responsive_builder.dart';

class _GraphQLEndpointDialog extends StatefulWidget {
  final String initialEndpoint;
  final Function(String) onSave;

  const _GraphQLEndpointDialog({
    required this.initialEndpoint,
    required this.onSave,
  });

  @override
  _GraphQLEndpointDialogState createState() => _GraphQLEndpointDialogState();
}

class _GraphQLEndpointDialogState extends State<_GraphQLEndpointDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _endpointController;
  bool _isLoading = false;
  bool? _isValid;
  Timer? _debounce;
  String _lastValidatedText = '';

  @override
  void initState() {
    super.initState();
    _endpointController = TextEditingController(text: widget.initialEndpoint);
    _lastValidatedText = widget.initialEndpoint;
    _endpointController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _endpointController.removeListener(_onTextChanged);
    _endpointController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    final currentText = _endpointController.text.trim();
    if (currentText != _lastValidatedText) {
      _validateEndpoint();
    }
  }

  Future<void> _validateEndpoint() async {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final endpoint = _endpointController.text.trim();

      if (endpoint == _lastValidatedText) return;

      _lastValidatedText =
          endpoint; // Update last validated text before starting validation

      if (endpoint.isEmpty) {
        setState(() {
          _isValid = false;
          _isLoading = false;
        });
        return;
      }

      setState(() => _isLoading = true);

      try {
        final isValid = await _isValidGraphQLEndpoint(endpoint);

        if (mounted) {
          setState(() {
            _isValid = isValid;
            _isLoading = false;
          });
        }
      } catch (e) {
        setState(() {
          _isValid = false;
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return ArDriveStandardModalNew(
      width: 500,
      title: 'Switch GraphQL Server',
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 500,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter the URL of the GraphQL server you want to use',
                style: typography.paragraphNormal(
                  color: colorTokens.textMid,
                ),
              ),
              const SizedBox(height: 16),
              ArDriveTextFieldNew(
                controller: _endpointController,
                hintText: 'Enter host name (e.g. https://ardrive.net)',
                label: 'GraphQL Server URL',
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a URL';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              _isLoading
                  ? Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              colorTokens.buttonPrimaryDefault,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Validating endpoint...',
                          style: typography.paragraphSmall(
                            color: colorTokens.textMid,
                          ),
                        ),
                      ],
                    )
                  : _endpointController.text.isNotEmpty && _isValid == false
                      ? Row(
                          children: [
                            Icon(
                              Icons.error,
                              size: 16,
                              color: colorTokens.buttonPrimaryPress,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Invalid GraphQL endpoint',
                              style: typography.paragraphSmall(
                                color: colorTokens.buttonPrimaryPress,
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
            ],
          ),
        ),
      ),
      actions: [
        ModalAction(
          title: 'Cancel',
          action: () => Navigator.of(context).pop(),
        ),
        ModalAction(
          title: 'Save',
          isEnable: _isValid == true && !_isLoading,
          action: () {
            if (_formKey.currentState!.validate()) {
              widget.onSave(_endpointController.text.trim());
              Navigator.of(context).pop();
            }
          },
        ),
      ],
    );
  }

  Future<bool> _isValidGraphQLEndpoint(String endpoint) async {
    const query = '''
      query {
        __typename
      }
    ''';

    final response = await http
        .post(
          Uri.parse('$endpoint/graphql'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'query': query}),
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      return jsonResponse['data'] != null &&
          jsonResponse['data']['__typename'] == 'Query';
    }
    return false;
  }
}

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
    final walletAddress = state.user.walletAddress;

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
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
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
                if (state.user.wallet is! ArConnectWallet) ...[
                  const SizedBox(height: 8),
                ],
                const Divider(
                  height: 21,
                  indent: 16,
                  endIndent: 16,
                ),
                _buildBalanceRow(context, state),
                if (isArioSDKSupportedOnPlatform())
                  _buildIOTokenRow(context, state),
                if (context.read<PaymentService>().useTurboPayment) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 20.0),
                    child: TurboBalance(
                      paymentService: context.read<PaymentService>(),
                      wallet: state.user.wallet,
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
            automaticallyCloseWhenOpenAnotherItem: true,
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
                    text: 'Send',
                    onTap: () {
                      _closeProfileCardMobile();

                      openUrl(url: Resources.sendGiftLink);
                    },
                  ),
                  _ProfileMenuAccordionItem(
                    text: 'Reedem',
                    onTap: () {
                      _closeProfileCardMobile();

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
                      _closeProfileCardMobile();
                    },
                  ),
                  _ProfileMenuAccordionItem(
                    text: 'Leave Feedback',
                    onTap: () {
                      openFeedbackSurveyUrl();
                      _closeProfileCardMobile();
                    },
                  ),
                  _ProfileMenuAccordionItem(
                    text: 'Share Logs',
                    onTap: () {
                      _closeProfileCardMobile();

                      shareLogs(
                        context: context,
                      );
                    },
                  ),
                ],
              ),
              ArDriveAccordionItem(
                Text(
                  'Advanced Settings',
                  style: typography.paragraphNormal(
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
                [
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 16.0, right: 16),
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
                              config.copyWith(
                                autoSync: value,
                              ),
                            );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 16.0, right: 16),
                    child: ArDriveToggleSwitch(
                      alignRight: true,
                      value:
                          context.read<ConfigService>().config.uploadThumbnails,
                      text: 'Upload with thumbnails',
                      textStyle: typography.paragraphNormal(
                        fontWeight: ArFontWeight.semiBold,
                        color: colorTokens.textMid,
                      ),
                      onChanged: (value) {
                        final config = context.read<ConfigService>().config;
                        context.read<ConfigService>().updateAppConfig(
                              config.copyWith(
                                uploadThumbnails: value,
                              ),
                            );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 16.0, right: 16),
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
                              config.copyWith(
                                enableSyncFromSnapshot: value,
                              ),
                            );
                      },
                    ),
                  ),
                  if (isArioSDKSupportedOnPlatform()) ...[
                    const SizedBox(height: 8),
                    _ProfileMenuAccordionItem(
                      text: 'Switch Gateway',
                      onTap: () {
                        setState(() {
                          _showProfileCard = false;
                        });
                        showGatewaySwitcherModal(context);
                      },
                    ),
                    Padding(
                      padding:
                          const EdgeInsets.only(left: 16.0, right: 16, top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current Gateway:',
                            style: typography.paragraphNormal(
                              fontWeight: ArFontWeight.semiBold,
                            ),
                          ),
                          Text(
                            configService
                                .config.defaultArweaveGatewayForDataRequest.url,
                            style: typography.paragraphNormal(
                              fontWeight: ArFontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _ProfileMenuAccordionItem(
                      text: 'Switch GraphQL Server',
                      onTap: () {
                        setState(() {
                          _showProfileCard = false;
                        });
                        // TODO: Show GraphQL endpoint switcher modal
                        _showGQLServerDialog(context);
                      },
                    ),
                    Padding(
                      padding:
                          const EdgeInsets.only(left: 16.0, right: 16, top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current GraphQL Server:',
                            style: typography.paragraphNormal(
                              fontWeight: ArFontWeight.semiBold,
                            ),
                          ),
                          Text(
                            configService.config.defaultArweaveGatewayUrl ??
                                'Not set',
                            style: typography.paragraphNormal(
                              fontWeight: ArFontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                  ],
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12.0, left: 16, top: 12),
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
          Padding(
            padding: const EdgeInsets.only(top: 20.0),
            child: _LogoutButton(
              onLogout: () {
                _showProfileCard = false;
                setState(() {});
              },
            ),
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
    final walletAddress = state.user.walletAddress;
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
              if (state.user.profileType != ProfileType.arConnect)
                ArDriveIconButton(
                  icon: ArDriveIcons.download(
                    color: colorTokens.textHigh,
                    size: 21,
                  ),
                  onPressed: () {
                    showDownloadWalletModal(context);
                  },
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
    final walletBalance =
        convertWinstonToLiteralString(state.user.walletBalance);
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

  void _closeProfileCardMobile() {
    Navigator.of(context).pop();
  }

  Future<void> _showGQLServerDialog(BuildContext context) async {
    await showAnimatedDialogWithBuilder(
      context,
      builder: (context) => _GraphQLEndpointDialog(
        initialEndpoint:
            context.read<ConfigService>().config.defaultArweaveGatewayUrl ?? '',
        onSave: (newEndpoint) {
          const graphqlSuffix = '/graphql';
          final normalizedEndpoint = newEndpoint.endsWith(graphqlSuffix)
              ? newEndpoint.substring(
                  0, newEndpoint.length - graphqlSuffix.length)
              : newEndpoint;
          final configService = context.read<ConfigService>();
          configService.updateAppConfig(
            configService.config.copyWith(
              defaultArweaveGatewayUrl: normalizedEndpoint,
            ),
          );
          context
              .read<ArweaveService>()
              .updateGraphQLEndpoint(normalizedEndpoint);
        },
      ),
    );
  }

  Widget _buildProfileCardHeader(BuildContext context, String walletAddress) {
    return ProfileCardHeader(
      walletAddress: walletAddress,
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
    final colors = ArDriveTheme.of(context).themeData.colorTokens;

    return ArDriveClickArea(
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: 16.0, right: 15),
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

  const ProfileCardHeader({
    super.key,
    required this.walletAddress,
    required this.onPressed,
    this.isExpanded = false,
    this.hasLogoutButton = false,
    this.onClickLogout,
    this.logoutTooltip,
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

    return truncateString(walletAddress, offsetStart: 2, offsetEnd: 2);
  }

  double _calculateMaxWidth(String primaryName, ProfileNameState state) {
    if (state is! ProfileNameLoaded && !isExpanded) {
      return 100;
    }

    double width = primaryName.length * 20;

    return width.clamp(110, 230);
  }

  Widget? _buildProfileIcon(ProfileNameLoaded state) {
    if (state.primaryNameDetails.logo == null) {
      return null;
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ClipOval(
        child: ArDriveImage(
          image: NetworkImage(
            'https://ardrive.net/${state.primaryNameDetails.logo}',
          ),
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
              Flexible(
                child: Text(
                  isExpanded ? state.walletAddress! : truncatedWalletAddress,
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
                if (icon != null) icon,
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
                                ? state.walletAddress
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

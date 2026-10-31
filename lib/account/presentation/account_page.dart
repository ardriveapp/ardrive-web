import 'package:ardrive/account/data/ethereum_wallet_detection.dart';
import 'package:ardrive/app_shell.dart';
import 'package:ardrive/arns/data/arns_wallet_store.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/arns/presentation/names_page/names_page.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/components/list_page/list_page_layout.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/device_unlock/data/device_tabs.dart';
import 'package:ardrive/drives_list/presentation/open_drive_on_selection.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/services/solana/solana_provider.dart';
import 'package:ardrive/user/download_wallet/download_wallet_modal.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/io_utils.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/truncate_string.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

/// The Account and security page in the app shell: a drive chosen in the
/// sidebar opens it, as on the Names page.
class AccountShell extends StatelessWidget {
  const AccountShell({super.key, required this.onOpenDrive});

  final void Function(String driveId) onOpenDrive;

  @override
  Widget build(BuildContext context) {
    return OpenDriveOnSelection(
      selections: context.read<DrivesCubit>().driveSelections,
      onOpenDrive: onOpenDrive,
      child: const AppShell(page: AccountPage()),
    );
  }
}

/// How an account signs in, which decides what the page offers.
enum AccountSignInKind {
  /// A keyfile, recovery phrase or generated account: its password opens
  /// the wallet stored on this device, and the keyfile is its backup.
  keyfile,

  /// Wander holds the key.
  wander,

  /// Phantom or Solflare: the Arweave wallet is made from its signature.
  solana,

  /// MetaMask: the Arweave wallet is made from its signature.
  ethereum,
}

/// [user]'s sign-in, from what the profile records.
AccountSignInKind accountSignInKindOf(User user) {
  if (user.profileType == ProfileType.arConnect) {
    return AccountSignInKind.wander;
  }
  final source = user.sourceWalletAddress;
  if (source == null) return AccountSignInKind.keyfile;
  return source.startsWith('0x')
      ? AccountSignInKind.ethereum
      : AccountSignInKind.solana;
}

/// The Solana wallet's name for the bridge's [provider] ('phantom' or
/// 'solflare'), or null when it isn't one of those.
String? solanaWalletName(String? provider) => switch (provider) {
      'phantom' => 'Phantom',
      'solflare' => 'Solflare',
      _ => null,
    };

/// Which Solana wallet signed this session in. The profile doesn't record
/// it: the wallet this session connected, or the only one installed.
String? _detectSolanaProvider() {
  try {
    final service = SolanaProviderService();
    final active = service.activeProvider();
    if (active != null) return active;
    final found = service.detectProviders();
    if (found.hasPhantom && !found.hasSolflare) return 'phantom';
    if (found.hasSolflare && !found.hasPhantom) return 'solflare';
  } catch (_) {
    // No bridge: the generic name.
  }
  return null;
}

/// Copies [text] and says whether it worked: a browser can refuse.
Future<void> copyWithToast(BuildContext context, String text) async {
  final strings = appLocalizationsOf(context);
  final messenger = ScaffoldMessenger.maybeOf(context);

  // Asked for at once, inside the tap: a browser refuses a later write.
  final write = Clipboard.setData(ClipboardData(text: text));
  bool copied;
  try {
    await write;
    copied = true;
  } catch (_) {
    copied = false;
  }

  if (messenger == null) return;
  showArDriveToast(
    messenger,
    text: copied ? strings.copied : strings.couldNotCopy,
    type: copied ? ArDriveStatusType.success : ArDriveStatusType.error,
    duration: const Duration(seconds: 2),
  );
}

/// The copy icon beside an address, named for a screen reader.
class AddressCopyButton extends StatelessWidget {
  const AddressCopyButton({
    super.key,
    required this.address,
    required this.label,
  });

  final String address;

  /// What a screen reader and the tooltip call it: "Copy Arweave address".
  final String label;

  /// The tap target's side, whatever the icon's size.
  static const double targetSize = 40;

  @override
  Widget build(BuildContext context) {
    void copy() => copyWithToast(context, address);

    // An icon button's own tap area is its 20 px icon: this one takes taps
    // across the whole 40 px square. A button to a screen reader, named by
    // [label]; Tab reaches it.
    return Semantics(
      button: true,
      label: label,
      onTap: copy,
      excludeSemantics: true,
      child: ArDriveFocusable(
        onActivate: copy,
        radius: ArDriveRadius.control,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: copy,
          child: HoverWidget(
            tooltip: label,
            hoverScale: 1.0,
            padding: EdgeInsets.zero,
            child: SizedBox.square(
              dimension: targetSize,
              child: Center(
                child: ArDriveIcons.copy(
                  size: 20,
                  color: ArDriveTheme.of(context).themeData.colorTokens.iconMid,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Account and security: how the account signs in, what this device
/// remembers, and the account's addresses. Full screen with a back arrow on
/// a phone; in the main area on desktop.
class AccountPage extends StatelessWidget {
  const AccountPage({super.key, this.solanaProvider});

  /// 'phantom' or 'solflare', for a Solana sign-in. Detected when null.
  final String? solanaProvider;

  @override
  Widget build(BuildContext context) {
    final body = AccountSections(solanaProvider: solanaProvider);
    return ScreenTypeLayout.builder(
      mobile: (context) => _PhonePage(child: body),
      desktop: (context) => ListPageChrome(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListPageTitleRow(
                title: ListPageTitleRow.text(
                  context,
                  appLocalizationsOf(context).accountAndSecurity,
                ),
              ),
              const SizedBox(height: listPageBlockGap),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: listPagePadding,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: body,
                ),
              ),
              const SizedBox(height: listPageSectionGap),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhonePage extends StatelessWidget {
  const _PhonePage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final strings = appLocalizationsOf(context);
    return Scaffold(
      backgroundColor: colors.containerL0,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ArDriveSpacing.xs,
                ArDriveSpacing.xs,
                ArDriveSpacing.md,
                ArDriveSpacing.xs,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: ArDriveIconButton(
                        key: const Key('accountBack'),
                        tooltip: strings.accountBack,
                        icon: ArDriveIcons.arrowLeft(
                          size: 24,
                          color: colors.iconHigh,
                        ),
                        onPressed: () =>
                            context.read<AppRouterDelegate>().closeAccount(),
                      ),
                    ),
                  ),
                  const SizedBox(width: ArDriveSpacing.xxs),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        strings.accountAndSecurity,
                        style: ArDriveTypographyNew.of(context).heading5(
                          color: colors.textHigh,
                          fontWeight: ArFontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  ArDriveSpacing.md,
                  ArDriveSpacing.xs,
                  ArDriveSpacing.md,
                  ArDriveSpacing.lg,
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The page's three sections, for the signed-in user.
class AccountSections extends StatelessWidget {
  const AccountSections({
    super.key,
    this.solanaProvider,
    this.ioUtils,
    this.tabs,
    this.metaMask,
  });

  /// See [AccountPage.solanaProvider].
  final String? solanaProvider;

  /// Saves the keyfile; a test passes its own.
  final ArDriveIOUtils? ioUtils;

  /// Told which drives Forget forgot, for the other tabs;
  /// [DeviceTabs.instance] unless a test passes its own.
  final DeviceTabs? tabs;

  /// Whether MetaMask is the browser's Ethereum wallet. Detected when null.
  final bool? metaMask;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        if (state is! ProfileLoggedIn) return const SizedBox.shrink();
        final user = state.user;
        final kind = accountSignInKindOf(user);
        final strings = appLocalizationsOf(context);
        final walletName = switch (kind) {
          AccountSignInKind.wander => 'Wander',
          // Named only when MetaMask is positively there: other Ethereum
          // wallets sign in the same way.
          AccountSignInKind.ethereum => (metaMask ?? metaMaskDetected())
              ? 'MetaMask'
              : strings.accountEthereumWallet,
          AccountSignInKind.solana =>
            solanaWalletName(solanaProvider ?? _detectSolanaProvider()) ??
                strings.accountSolanaWallet,
          AccountSignInKind.keyfile => null,
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Section(
              title: strings.accountSignInSection,
              rows: [
                if (kind == AccountSignInKind.keyfile)
                  _AccountRow(
                    key: const Key('accountKeyfileRow'),
                    title: strings.accountKeyfile,
                    trailing: _RowButton(
                      key: const Key('accountKeyfileDownload'),
                      text: strings.accountDownload,
                      // Asks for the password before it downloads.
                      onPressed: () =>
                          showDownloadWalletModal(context, ioUtils: ioUtils),
                    ),
                  )
                else
                  _AccountRow(
                    key: const Key('accountSignInWalletRow'),
                    title: walletName!,
                    note: kind == AccountSignInKind.wander
                        ? strings.accountWanderKeepsYourKey
                        : strings.accountWalletSignsYouIn(walletName),
                    trailing: _StatusLabel(strings.accountConnected),
                  ),
              ],
            ),
            _Section(
              title: strings.accountThisDeviceSection,
              rows: [_RememberedDrivesRow(tabs: tabs ?? DeviceTabs.instance)],
            ),
            _Section(
              title: strings.accountAddressesSection,
              rows: _addressRows(context, user, kind),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _addressRows(
    BuildContext context,
    User user,
    AccountSignInKind kind,
  ) {
    final strings = appLocalizationsOf(context);
    final source = user.sourceWalletAddress;
    final arweave = _AddressRow(
      key: const Key('accountArweaveAddress'),
      title: strings.accountArweaveForFiles,
      address: user.walletAddress,
      copyLabel: strings.accountCopyAddress('Arweave'),
    );

    switch (kind) {
      case AccountSignInKind.solana:
        // By default the sign-in wallet is the names wallet, so there is no
        // Link. Another one linked since (the name dialog's Change wallet),
        // or none, gets its own row, with Unlink or Link.
        final namesWallet = _namesWalletOf(context);
        final signInIsNames =
            namesWallet.on && namesWallet.linked?.address == source;
        return [
          _AddressRow(
            key: const Key('accountSolanaAddress'),
            title: signInIsNames
                ? strings.accountSolanaForSignInAndNames
                : strings.accountSolanaForSignIn,
            address: source!,
            copyLabel: strings.accountCopyAddress('Solana'),
          ),
          arweave,
          if (namesWallet.on && !signInIsNames) const NamesWalletRow(),
        ];
      case AccountSignInKind.ethereum:
        return [
          _AddressRow(
            key: const Key('accountEthereumAddress'),
            title: strings.accountEthereumForSignIn,
            address: source!,
            copyLabel: strings.accountCopyAddress('Ethereum'),
          ),
          arweave,
          const NamesWalletRow(),
        ];
      case AccountSignInKind.keyfile:
      case AccountSignInKind.wander:
        return [arweave, const NamesWalletRow()];
    }
  }
}

/// Whether names are on here, and the names wallet linked, if any. Watched,
/// so the rows follow a link or an unlink.
({bool on, LinkedArNSWallet? linked}) _namesWalletOf(BuildContext context) {
  if (!_namesOn(context)) return (on: false, linked: null);
  try {
    final state = context.watch<ArNSWalletCubit>().state;
    if (state.status == ArNSWalletStatus.unavailable) {
      return (on: false, linked: null);
    }
    return (on: true, linked: state.linked);
  } on ProviderNotFoundException {
    return (on: false, linked: null);
  }
}

/// Whether names are on, so a Solana wallet can be linked for them.
bool _namesOn(BuildContext context) {
  try {
    return context.read<ConfigService>().config.enableArNS;
  } on ProviderNotFoundException {
    return false;
  }
}

/// "Solana, for names": Link when none is linked; otherwise its address,
/// copy and Unlink. Nothing while names are off.
class NamesWalletRow extends StatelessWidget {
  const NamesWalletRow({super.key});

  @override
  Widget build(BuildContext context) {
    final ArNSWalletCubit cubit;
    try {
      // Checked first, so nothing is built while names are off.
      if (!_namesOn(context)) return const SizedBox.shrink();
      cubit = context.read<ArNSWalletCubit>();
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    return BlocBuilder<ArNSWalletCubit, ArNSWalletState>(
      bloc: cubit,
      builder: (context, state) {
        if (state.status == ArNSWalletStatus.unavailable) {
          return const SizedBox.shrink();
        }
        final strings = appLocalizationsOf(context);
        final linked = state.linked;
        if (linked == null) {
          return _AccountRow(
            key: const Key('accountNamesWallet'),
            title: strings.accountSolanaForNames,
            trailing: _RowButton(
              key: const Key('accountNamesLink'),
              text: strings.accountLink,
              onPressed: () => showArNSWalletDialog(context),
            ),
          );
        }
        return _AddressRow(
          key: const Key('accountNamesWallet'),
          title: strings.accountSolanaForNames,
          address: linked.address,
          copyLabel: strings.accountCopyAddress('Solana'),
          action: _RowButton(
            key: const Key('accountNamesUnlink'),
            text: strings.arnsUnlink,
            onPressed: cubit.unlink,
          ),
        );
      },
    );
  }
}

/// "2 drives remembered · Forget", or "No drives remembered".
class _RememberedDrivesRow extends StatelessWidget {
  const _RememberedDrivesRow({required this.tabs});

  final DeviceTabs tabs;

  @override
  Widget build(BuildContext context) {
    final driveDao = context.read<DriveDao>();
    final auth = context.read<ArDriveAuth>();
    final String owner;
    try {
      owner = auth.currentUser.walletAddress;
    } on AuthenticationUserIsNotLoggedInException {
      return const SizedBox.shrink();
    }
    final strings = appLocalizationsOf(context);

    return StreamBuilder<int>(
      stream: driveDao.watchRememberedDriveKeyCount(ownerAddress: owner),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        if (count == 0) {
          return _AccountRow(
            key: const Key('accountRememberedDrives'),
            title: strings.accountNoDrivesRemembered,
          );
        }
        return _AccountRow(
          key: const Key('accountRememberedDrives'),
          title: strings.accountDrivesRemembered(count),
          trailing: _RowButton(
            key: const Key('accountForgetDrives'),
            text: strings.forget,
            onPressed: () async {
              final confirmed = await showArDriveDialogWithBuilder<bool>(
                context,
                builder: (dialogContext) =>
                    ForgetAllOnThisDeviceDialog(count: count),
              );
              await forgetAllIfConfirmed(
                confirmed: confirmed,
                driveDao: driveDao,
                user: auth.currentUser,
                tabs: tabs,
              );
            },
          ),
        );
      },
    );
  }
}

/// A heading and its rows on one card, divided.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final theme = ArDriveTheme.of(context).themeData;
    final colors = theme.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: ArDriveSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: ArDriveSpacing.xxs,
              bottom: ArDriveSpacing.xs,
            ),
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: typography.paragraphNormal(
                  color: colors.textLow,
                  fontWeight: ArFontWeight.semiBold,
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.tableTheme.backgroundColor,
              borderRadius: BorderRadius.circular(ArDriveRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: colors.strokeLow,
                      indent: ArDriveSpacing.md,
                      endIndent: ArDriveSpacing.md,
                    ),
                  rows[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One row: a title, an optional address or note under it, and what it
/// offers on the right.
class _AccountRow extends StatelessWidget {
  const _AccountRow({
    super.key,
    required this.title,
    this.subtitle,
    this.note,
    this.trailing,
  });

  final String title;
  final Widget? subtitle;
  final String? note;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final note = this.note;
    final trailing = this.trailing;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ArDriveSpacing.md,
          vertical: ArDriveSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: typography.paragraphNormal(
                      color: colors.textHigh,
                      fontWeight: ArFontWeight.semiBold,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: ArDriveSpacing.xxs),
                    subtitle!,
                  ],
                  if (note != null) ...[
                    const SizedBox(height: ArDriveSpacing.xxs),
                    Text(
                      note,
                      style: typography.paragraphSmall(
                        color: colors.textLow,
                        fontWeight: ArFontWeight.book,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: ArDriveSpacing.sm),
              trailing,
            ],
          ],
        ),
      ),
    );
  }
}

/// An address row: its use, the short address in monospace, and copy, with
/// an optional [action] beside it.
class _AddressRow extends StatelessWidget {
  const _AddressRow({
    super.key,
    required this.title,
    required this.address,
    required this.copyLabel,
    this.action,
  });

  final String title;
  final String address;
  final String copyLabel;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final action = this.action;

    return _AccountRow(
      title: title,
      subtitle: ArDriveIdText(
        shortenId(address),
        style: typography.code(fontSize: 13, color: colors.textLow),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AddressCopyButton(address: address, label: copyLabel),
          if (action != null) ...[
            const SizedBox(width: ArDriveSpacing.sm),
            action,
          ],
        ],
      ),
    );
  }
}

class _RowButton extends StatelessWidget {
  const _RowButton({super.key, required this.text, required this.onPressed});

  final String text;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ArDriveButtonNew(
      text: text,
      typography: ArDriveTypographyNew.of(context),
      variant: ButtonVariant.secondary,
      size: ArDriveButtonSize.compact,
      onPressed: onPressed,
    );
  }
}

/// "Connected", beside the wallet that signs this account in.
class _StatusLabel extends StatelessWidget {
  const _StatusLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: ArDriveTypographyNew.of(context).paragraphNormal(
        color: ArDriveTheme.of(context).themeData.colorTokens.textLow,
        fontWeight: ArFontWeight.book,
      ),
    );
  }
}

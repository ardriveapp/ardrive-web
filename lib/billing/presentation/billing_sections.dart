import 'dart:typed_data';

import 'package:ardrive/account/presentation/account_page.dart';
import 'package:ardrive/billing/bloc/billing_cubit.dart';
import 'package:ardrive/billing/data/billing_session_cache.dart';
import 'package:ardrive/billing/data/purchase.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/account/data/ethereum_wallet_detection.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/turbo/models/turbo_free_allowance.dart';
import 'package:ardrive/turbo/services/credit_sharing_service.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/topup/views/topup_modal.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/truncate_string.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

/// Saves a CSV with the app's file saver.
Future<void> saveCsvWithArDriveIO(String name, Uint8List bytes) async {
  await ArDriveIO().saveFile(
    await IOFile.fromData(
      bytes,
      name: name,
      lastModifiedDate: DateTime.now(),
      contentType: 'text/csv',
    ),
  );
}

/// The page's sections, for the signed-in user.
class BillingSections extends StatelessWidget {
  const BillingSections({
    super.key,
    this.solanaProvider,
    this.metaMask,
    this.creditSharing,
    this.saveCsv,
  });

  /// 'phantom' or 'solflare' for a Solana sign-in; detected when null.
  final String? solanaProvider;

  /// Whether MetaMask is the browser's Ethereum wallet; detected when null.
  final bool? metaMask;

  /// Shares the sign-in wallet's credits; built from the config when null.
  final CreditSharingService? creditSharing;

  /// Saves the CSV; the app's file saver when null.
  final SaveCsv? saveCsv;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        if (state is! ProfileLoggedIn) return const SizedBox.shrink();
        final user = state.user;
        final kind = accountSignInKindOf(user);

        // One cubit per account: a different wallet gets a fresh page.
        return BlocProvider(
          key: ValueKey(user.walletAddress),
          create: (context) => BillingCubit(
            user: user,
            paymentService: context.read<PaymentService>(),
            cache: context.read<BillingSessionCache>(),
            saveCsv: saveCsv ?? saveCsvWithArDriveIO,
            creditSharing: creditSharing ??
                CreditSharingService.fromConfig(context.read<ConfigService>()),
            asksBeforePurchases: kind == AccountSignInKind.wander,
          )..load(),
          child: _BillingBody(
            kind: kind,
            walletName: _walletName(context, kind),
          ),
        );
      },
    );
  }

  String? _walletName(BuildContext context, AccountSignInKind kind) {
    final strings = appLocalizationsOf(context);
    return switch (kind) {
      AccountSignInKind.solana =>
        solanaWalletName(solanaProvider ?? detectSolanaProvider()) ??
            strings.accountSolanaWallet,
      AccountSignInKind.ethereum => (metaMask ?? metaMaskDetected())
          ? 'MetaMask'
          : strings.accountEthereumWallet,
      _ => null,
    };
  }
}

class _BillingBody extends StatelessWidget {
  const _BillingBody({required this.kind, required this.walletName});

  final AccountSignInKind kind;
  final String? walletName;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BillingCubit, BillingState>(
      builder: (context, state) {
        final hasShares =
            state.balance.given.isNotEmpty || state.balance.received.isNotEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BalanceSection(kind: kind, walletName: walletName, state: state),
            _PurchasesSection(
              kind: kind,
              walletName: walletName,
              state: state,
            ),
            if (hasShares) _SharedCreditsSection(balance: state.balance),
          ],
        );
      },
    );
  }
}

// ---- balance ----------------------------------------------------------------

class _BalanceSection extends StatelessWidget {
  const _BalanceSection({
    required this.kind,
    required this.walletName,
    required this.state,
  });

  final AccountSignInKind kind;
  final String? walletName;
  final BillingState state;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final user = context.select<ProfileCubit, User?>((cubit) {
      final s = cubit.state;
      return s is ProfileLoggedIn ? s.user : null;
    });
    final ar = user?.walletBalance ?? BigInt.zero;
    final crypto =
        kind == AccountSignInKind.solana || kind == AccountSignInKind.ethereum;
    // Phantom and MetaMask accounts almost never hold AR: only when they do.
    final showAr = !crypto || ar > BigInt.zero;
    final credits = state.sourceCredits;

    return PageSection(
      title: strings.billingBalanceSection,
      rows: [
        _BalanceCard(state: state),
        if (showAr)
          PageRow(
            key: const Key('billingArRow'),
            title: strings.billingArRow,
            trailing: Text(
              '${convertWinstonToLiteralString(ar)} AR',
              style: ArDriveTypographyNew.of(context).paragraphNormal(
                color: ArDriveTheme.of(context).themeData.colorTokens.textHigh,
                fontWeight: ArFontWeight.semiBold,
              ),
            ),
          ),
        if (credits != null)
          _SourceCreditsRow(
            credits: credits,
            walletName: walletName ?? '',
            state: state,
          ),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.state});

  final BillingState state;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final cubit = context.read<BillingCubit>();
    final balance = state.balance;

    final small = typography.paragraphNormal(
      color: colors.textLow,
      fontWeight: ArFontWeight.book,
    );

    void addCredits() {
      showTurboTopupModal(
        context,
        onSuccess: () {
          if (!context.mounted) return;
          context.read<ProfileCubit>().refreshBalance();
          cubit.refreshAfterTopUp();
        },
      );
    }

    final Widget figure;
    switch (balance.status) {
      case LoadStatus.loading:
        figure = const Padding(
          padding: EdgeInsets.symmetric(vertical: ArDriveSpacing.xs),
          child: ArDriveSpinner(
            key: Key('billingBalanceLoading'),
            size: ArDriveSpinnerSize.small,
          ),
        );
      case LoadStatus.error:
        // Never 0: a failed read says so.
        figure = Row(
          key: const Key('billingBalanceError'),
          children: [
            Flexible(
              child: Text(
                strings.billingBalanceError,
                style: typography.paragraphNormal(
                  color: colors.textMid,
                  fontWeight: ArFontWeight.semiBold,
                ),
              ),
            ),
            const SizedBox(width: ArDriveSpacing.sm),
            PageRowButton(
              key: const Key('billingBalanceRetry'),
              text: strings.tryAgain,
              onPressed: cubit.loadBalance,
            ),
          ],
        );
      case LoadStatus.ready:
        final storage = state.storageGiB;
        figure = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label:
                  '${strings.billingTurboCredits} ${convertWinstonToLiteralString(balance.effective)}',
              excludeSemantics: true,
              child: Text(
                convertWinstonToLiteralString(balance.effective),
                key: const Key('billingBalanceFigure'),
                style: typography.heading2(
                  color: colors.textHigh,
                  fontWeight: ArFontWeight.bold,
                ),
              ),
            ),
            if (storage != null && storage > 0)
              Text(
                strings.billingStorageEstimate(
                  formatStorageWithDynamicUnit(storage, includeApprox: false),
                ),
                key: const Key('billingStorage'),
                style: small,
              ),
            if (balance.shared > BigInt.zero)
              Text(
                strings.billingYoursAndShared(
                  convertWinstonToLiteralString(balance.own),
                  convertWinstonToLiteralString(balance.shared),
                ),
                key: const Key('billingYoursAndShared'),
                style: small,
              ),
            ..._freeAllowance(context, small),
          ],
        );
    }

    return Padding(
      padding: const EdgeInsets.all(ArDriveSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.billingTurboCredits,
            style: typography.paragraphNormal(
              color: colors.textMid,
              fontWeight: ArFontWeight.semiBold,
            ),
          ),
          const SizedBox(height: ArDriveSpacing.xxs),
          figure,
          const SizedBox(height: ArDriveSpacing.sm),
          ArDriveButtonNew(
            key: const Key('billingAddCredits'),
            text: strings.addCredits,
            typography: typography,
            variant: ButtonVariant.primary,
            size: ArDriveButtonSize.compact,
            onPressed: addCredits,
          ),
        ],
      ),
    );
  }

  List<Widget> _freeAllowance(BuildContext context, TextStyle style) {
    final strings = appLocalizationsOf(context);
    final allowance = state.freeAllowance;
    if (allowance == null) return const [];
    switch (allowance.status) {
      case TurboFreeAllowanceStatus.limited:
      case TurboFreeAllowanceStatus.unlimited:
        return [
          Padding(
            padding: const EdgeInsets.only(top: ArDriveSpacing.xs),
            child: Text(
              strings.billingFreeAllowance,
              key: const Key('billingFreeAllowance'),
              style: style,
            ),
          ),
        ];
      case TurboFreeAllowanceStatus.disabled:
        return [
          Padding(
            padding: const EdgeInsets.only(top: ArDriveSpacing.xs),
            child: Text(
              strings.billingFreeAllowanceUsed,
              key: const Key('billingFreeAllowanceUsed'),
              style: style,
            ),
          ),
        ];
      case TurboFreeAllowanceStatus.unknown:
        return const [];
    }
  }
}

class _SourceCreditsRow extends StatelessWidget {
  const _SourceCreditsRow({
    required this.credits,
    required this.walletName,
    required this.state,
  });

  final dynamic credits;
  final String walletName;
  final BillingState state;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final cubit = context.read<BillingCubit>();
    final title = strings.billingSourceCredits(
      convertWinstonToLiteralString(credits.balance as BigInt),
      walletName,
    );

    if (cubit.canShareSourceCredits) {
      return PageRow(
        key: const Key('billingSourceCredits'),
        title: title,
        note: state.shareFailed ? strings.billingShareFailed : null,
        trailing: PageRowButton(
          key: const Key('billingUseCredits'),
          text: state.sharing ? strings.billingSharing : strings.billingUseThem,
          onPressed: state.sharing ? () {} : cubit.shareSourceCredits,
        ),
      );
    }

    // MetaMask, or no way to sign here: share them in the Console, to the
    // account's whole Arweave address.
    final address = credits.arweaveAddress as String;
    return PageRow(
      key: const Key('billingSourceCredits'),
      title: title,
      subtitle: Text(
        strings.billingShareInConsole,
        style: typography.paragraphSmall(
          color: colors.textLow,
          fontWeight: ArFontWeight.book,
        ),
      ),
      trailing: AddressCopyButton(
        key: const Key('billingCopyArweaveAddress'),
        address: address,
        label: strings.accountCopyAddress('Arweave'),
      ),
    );
  }
}

// ---- purchases --------------------------------------------------------------

class _PurchasesSection extends StatelessWidget {
  const _PurchasesSection({
    required this.kind,
    required this.walletName,
    required this.state,
  });

  final AccountSignInKind kind;
  final String? walletName;
  final BillingState state;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final cubit = context.read<BillingCubit>();
    final view = state.purchases;
    final other =
        kind == AccountSignInKind.solana || kind == AccountSignInKind.ethereum;

    final rows = <Widget>[];
    if (!view.started) {
      rows.add(PageRow(
        key: const Key('billingPurchasesStart'),
        title: strings.billingShowPurchases,
        note: strings.billingWanderApproves,
        trailing: PageRowButton(
          key: const Key('billingShowPurchases'),
          text: strings.billingShowPurchases,
          onPressed: cubit.loadPurchases,
        ),
      ));
    } else if (view.loading) {
      rows.add(const Padding(
        padding: EdgeInsets.all(ArDriveSpacing.md),
        child: Center(
          child: ArDriveSpinner(
            key: Key('billingPurchasesLoading'),
            size: ArDriveSpinnerSize.small,
          ),
        ),
      ));
    } else if (view.rows.isEmpty && view.failure != null) {
      rows.add(PageRow(
        key: const Key('billingPurchasesError'),
        title: view.failure == PurchasesFailure.refused
            ? strings.billingPurchasesRefused
            : strings.billingPurchasesError,
        trailing: PageRowButton(
          key: const Key('billingPurchasesRetry'),
          text: strings.tryAgain,
          onPressed: cubit.loadPurchases,
        ),
      ));
    } else if (view.rows.isEmpty) {
      rows.add(PageRow(
        key: const Key('billingPurchasesEmpty'),
        title: strings.billingNoPurchases,
        trailing: PageRowButton(
          key: const Key('billingEmptyAddCredits'),
          text: strings.addCredits,
          onPressed: () => showTurboTopupModal(
            context,
            onSuccess: () {
              if (!context.mounted) return;
              context.read<ProfileCubit>().refreshBalance();
              cubit.refreshAfterTopUp();
            },
          ),
        ),
      ));
    } else {
      for (final purchase in view.rows) {
        rows.add(_PurchaseRow(purchase: purchase));
      }
      rows.add(_PurchaseActions(state: state));
    }

    return PageSection(
      title: strings.billingPurchasesSection,
      rows: rows,
      footer: other && walletName != null
          ? Padding(
              padding: const EdgeInsets.only(
                left: ArDriveSpacing.xxs,
                top: ArDriveSpacing.xs,
              ),
              child: Text(
                strings.billingOtherWalletPurchases(walletName!),
                key: const Key('billingOtherWalletPurchases'),
                style: typography.paragraphSmall(
                  color: colors.textLow,
                  fontWeight: ArFontWeight.book,
                ),
              ),
            )
          : null,
    );
  }
}

class _PurchaseActions extends StatelessWidget {
  const _PurchaseActions({required this.state});

  final BillingState state;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final cubit = context.read<BillingCubit>();
    final view = state.purchases;

    return Padding(
      padding: const EdgeInsets.all(ArDriveSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (view.failure != null || state.csvFailed)
            Padding(
              padding: const EdgeInsets.only(bottom: ArDriveSpacing.xs),
              child: Text(
                state.csvFailed
                    ? strings.billingCsvError
                    : strings.billingPurchasesError,
                key: const Key('billingActionError'),
                style: typography.paragraphNormal(
                  color: colors.statusErrorFg,
                  fontWeight: ArFontWeight.book,
                ),
              ),
            ),
          Wrap(
            spacing: ArDriveSpacing.sm,
            runSpacing: ArDriveSpacing.xs,
            children: [
              if (view.hasMore)
                PageRowButton(
                  key: const Key('billingLoadMore'),
                  text: strings.billingLoadMore,
                  onPressed: view.loadingMore ? () {} : cubit.loadMore,
                ),
              PageRowButton(
                key: const Key('billingDownloadCsv'),
                text: strings.billingDownloadCsv,
                onPressed: view.savingCsv ? () {} : cubit.downloadCsv,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PurchaseRow extends StatelessWidget {
  const _PurchaseRow({required this.purchase});

  final Purchase purchase;

  String _short(String value) => value.length <= 12 ? value : shortenId(value);

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final p = purchase;

    final tag = switch (p.kind) {
      PurchaseKind.card => strings.billingCard,
      PurchaseKind.crypto => strings.billingCrypto,
      PurchaseKind.other => strings.billingOther,
    };
    final amount = switch (p.kind) {
      PurchaseKind.card =>
        p.isGrant ? strings.billingCreditGrant : p.cardAmountText,
      PurchaseKind.crypto => p.cryptoAmountText,
      PurchaseKind.other => p.detail,
    };
    final usd = p.usdText;
    final reference = p.reference;
    final explorer = p.explorerUri;

    final small = typography.paragraphSmall(
      color: colors.textLow,
      fontWeight: ArFontWeight.book,
    );

    Widget? referenceWidget;
    if (reference != null) {
      final text = reference.isTransaction
          ? _short(reference.value)
          : strings.billingReceipt(_short(reference.value));
      if (explorer != null) {
        referenceWidget = Semantics(
          link: true,
          label: strings.billingOpenTransaction(_short(reference.value)),
          excludeSemantics: true,
          onTap: () => openUrl(url: explorer.toString()),
          child: ArDriveFocusable(
            onActivate: () => openUrl(url: explorer.toString()),
            radius: ArDriveRadius.control,
            child: GestureDetector(
              onTap: () => openUrl(url: explorer.toString()),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      text,
                      key: const Key('billingReferenceLink'),
                      style:
                          typography.code(fontSize: 13, color: colors.textMid),
                    ),
                    const SizedBox(width: ArDriveSpacing.xxs),
                    ArDriveIcons.newWindow(size: 14, color: colors.iconMid),
                  ],
                ),
              ),
            ),
          ),
        );
      } else {
        referenceWidget = Text(
          text,
          style: typography.code(fontSize: 13, color: colors.textLow),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ArDriveSpacing.md,
        vertical: ArDriveSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: ArDriveSpacing.xs,
                  children: [
                    _Tag(tag),
                    if (amount != null)
                      Text(
                        amount,
                        style: typography.paragraphNormal(
                          color: colors.textHigh,
                          fontWeight: ArFontWeight.semiBold,
                        ),
                      ),
                    if (usd != null) Text(usd, style: small),
                  ],
                ),
                if (p.giftMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: ArDriveSpacing.xxs),
                    child: Text('"${p.giftMessage}"', style: small),
                  ),
                const SizedBox(height: ArDriveSpacing.xxs),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: ArDriveSpacing.xs,
                  children: [
                    Text(p.dateLabel, style: small),
                    if (referenceWidget != null) referenceWidget,
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: ArDriveSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (p.creditsText.isNotEmpty)
                Text(
                  '+${p.creditsText}',
                  style: typography.paragraphNormal(
                    color: colors.statusSuccessFg,
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
              if (reference != null && !reference.isTransaction)
                AddressCopyButton(
                  address: reference.value,
                  label: strings.billingCopyReceipt,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.containerL3,
        borderRadius: BorderRadius.circular(ArDriveRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ArDriveSpacing.xs,
          vertical: 2,
        ),
        child: Text(
          text,
          style: ArDriveTypographyNew.of(context).paragraphSmall(
            color: colors.textMid,
            fontWeight: ArFontWeight.semiBold,
          ),
        ),
      ),
    );
  }
}

// ---- shared credits -----------------------------------------------------------

class _SharedCreditsSection extends StatelessWidget {
  const _SharedCreditsSection({required this.balance});

  final BalanceView balance;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);

    return PageSection(
      title: strings.billingSharedSection,
      rows: [
        if (balance.received.isNotEmpty)
          _ShareGroup(
            key: const Key('billingSharedWithYou'),
            title: strings.billingSharedWithYou,
            shares: balance.received,
            received: true,
          ),
        if (balance.given.isNotEmpty)
          _ShareGroup(
            key: const Key('billingYouShared'),
            title: strings.billingYouShared,
            shares: balance.given,
            received: false,
          ),
      ],
    );
  }
}

class _ShareGroup extends StatelessWidget {
  const _ShareGroup({
    super.key,
    required this.title,
    required this.shares,
    required this.received,
  });

  final String title;
  final List<TurboCreditApproval> shares;
  final bool received;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    String expiry(TurboCreditApproval share) {
      final at = share.expiresAt;
      if (at == null) return strings.billingNeverExpires;
      if (at.isBefore(DateTime.now())) return strings.billingExpired;
      return strings.billingExpires(DateFormat.yMMMd().format(at.toLocal()));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ArDriveSpacing.md,
        vertical: ArDriveSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: typography.paragraphNormal(
                color: colors.textHigh,
                fontWeight: ArFontWeight.semiBold,
              ),
            ),
          ),
          for (final share in shares)
            Padding(
              padding: const EdgeInsets.only(top: ArDriveSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ArDriveIdText(
                          shortenId(
                            received
                                ? share.payingAddress
                                : share.approvedAddress,
                          ),
                          style: typography.code(
                            fontSize: 13,
                            color: colors.textMid,
                          ),
                        ),
                        Text(
                          received
                              ? '${strings.billingLeftOf(convertWinstonToLiteralString(share.leftWinc))} · ${expiry(share)}'
                              : '${strings.billingUsedOf(convertWinstonToLiteralString(share.usedWinc), convertWinstonToLiteralString(share.approvedWinc))} · ${expiry(share)}',
                          style: typography.paragraphSmall(
                            color: colors.textLow,
                            fontWeight: ArFontWeight.book,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

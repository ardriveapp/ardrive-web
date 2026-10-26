import 'package:ardrive/app_shell.dart';
import 'package:ardrive/arns/domain/arns_nameable_item.dart';
import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_chooser.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/arns/presentation/item/arns_item_names.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog_cubit.dart';
import 'package:ardrive/arns/presentation/names/arns_names_cubit.dart';
import 'package:ardrive/arns/presentation/widgets/arns_widgets.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/components/side_bar.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:responsive_builder/responsive_builder.dart';

/// From 30 days before a lease ends, "Renews in 12 days".
const arnsRenewalNoticeWindow = Duration(days: 30);

/// On the web › Names: every name and undername the ArNS wallet owns or
/// manages, what each points to and its cache time (docs/NAMES.md, "The
/// Names page"). Read from ArNS again each time it opens.
class ArNSNamesPage extends StatefulWidget {
  const ArNSNamesPage({super.key});

  @override
  State<ArNSNamesPage> createState() => _ArNSNamesPageState();
}

class _ArNSNamesPageState extends State<ArNSNamesPage> {
  @override
  void initState() {
    super.initState();
    context.read<ArNSNamesCubit>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenTypeLayout.builder(
      mobile: (context) => Scaffold(
        drawerScrimColor: ArDriveTheme.of(context)
            .themeData
            .colorTokens
            .containerL0
            .withOpacity(0.5),
        drawer: const AppSideBar(),
        appBar: const MobileAppBar(),
        body: const ArNSNamesView(isPhone: true),
      ),
      desktop: (context) => const Padding(
        padding: EdgeInsets.only(top: 32, right: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [ProfileCard()],
            ),
            SizedBox(height: ArDriveSpacing.lg),
            Expanded(child: ArNSNamesView(isPhone: false)),
          ],
        ),
      ),
    );
  }
}

/// The page's content, without the shell: the header and the names.
class ArNSNamesView extends StatelessWidget {
  const ArNSNamesView({super.key, required this.isPhone});

  final bool isPhone;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ArNSWalletCubit, ArNSWalletState>(
      builder: (context, wallet) => BlocBuilder<ArNSNamesCubit, ArNSNamesState>(
        builder: (context, names) {
          final padding = EdgeInsets.symmetric(
            horizontal: isPhone ? ArDriveSpacing.md : 0,
            vertical: isPhone ? ArDriveSpacing.md : 0,
          );
          final body = _body(context, wallet, names);
          return ListView(
            padding: padding.copyWith(bottom: ArDriveSpacing.xl),
            children: [
              _Header(wallet: wallet, names: names, isPhone: isPhone),
              const SizedBox(height: ArDriveSpacing.lg),
              ...body,
            ],
          );
        },
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    ArNSWalletState wallet,
    ArNSNamesState names,
  ) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;

    if (wallet.linked == null) {
      return [
        const SizedBox(height: ArDriveSpacing.xl),
        ArDriveEmptyState(
          icon: Icon(arnsNameIcon, size: 32, color: colors.iconLow),
          title: strings.arnsLinkWalletTitle,
          message: strings.arnsLinkWalletPageBody,
          actionLabel: strings.arnsLinkSolanaWallet,
          onAction: () => showArNSWalletDialog(context),
        ),
      ];
    }

    switch (names.status) {
      case ArNSNamesStatus.none:
      case ArNSNamesStatus.loading:
        return [
          const SizedBox(height: ArDriveSpacing.xl),
          const Center(child: ArDriveSpinner(size: ArDriveSpinnerSize.large)),
        ];
      case ArNSNamesStatus.failed:
        return [
          ArDriveNotice(
            type: ArDriveNoticeType.error,
            message: strings.arnsNamesCouldNotBeRead,
            actionLabel: strings.tryAgain,
            onAction: () => context.read<ArNSNamesCubit>().refresh(),
          ),
        ];
      case ArNSNamesStatus.loaded:
        break;
    }

    if (names.names.isEmpty) {
      return [
        const SizedBox(height: ArDriveSpacing.xl),
        const ArNSNoNames(),
      ];
    }

    final now = DateTime.now();
    return [
      if (names.refreshFailed) ...[
        ArDriveNotice(
          type: ArDriveNoticeType.warning,
          message: strings.arnsShowingLastRead,
          actionLabel: strings.tryAgain,
          onAction: () => context.read<ArNSNamesCubit>().refresh(),
        ),
        const SizedBox(height: ArDriveSpacing.md),
      ],
      for (final name in names.names)
        if (!name.isExpired(now)) ...[
          _NameCard(name: name, now: now, isPhone: isPhone),
          const SizedBox(height: ArDriveSpacing.md),
        ],
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.wallet,
    required this.names,
    required this.isPhone,
  });

  final ArNSWalletState wallet;
  final ArNSNamesState names;
  final bool isPhone;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final linked = wallet.linked;

    final title = Row(
      children: [
        Expanded(
          child: Text(
            strings.arnsNames,
            style: typography.heading3(
              color: colors.textHigh,
              fontWeight: ArFontWeight.bold,
            ),
          ),
        ),
        if (names.refreshing && names.status == ArNSNamesStatus.loaded)
          const Padding(
            padding: EdgeInsets.only(right: ArDriveSpacing.sm),
            child: ArDriveSpinner(),
          ),
        if (linked != null)
          ArDriveButtonNew(
            text: strings.arnsGetAName,
            typography: typography,
            variant: ButtonVariant.secondary,
            onPressed: () => openUrl(url: arnsConsoleUrl),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        title,
        const SizedBox(height: ArDriveSpacing.xxs),
        Text(
          strings.arnsNamesPageIntro,
          style: typography.paragraphNormal(color: colors.textMid),
        ),
        if (linked != null) ...[
          const SizedBox(height: ArDriveSpacing.xs),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: ArDriveSpacing.xs,
            children: [
              Text(
                strings.arnsWallet,
                style: typography.paragraphSmall(color: colors.textLow),
              ),
              ArDriveIdText(
                shortArNSAddress(linked.address),
                style: typography.code(color: colors.textMid, fontSize: 12),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _NameCard extends StatelessWidget {
  const _NameCard({
    required this.name,
    required this.now,
    required this.isPhone,
  });

  final ArNSManagedName name;
  final DateTime now;
  final bool isPhone;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final grace = name.isInGracePeriod(now);
    final end = name.endTimestamp;
    final placeholder =
        context.read<ConfigService>().config.arnsPlaceholderTxId;

    Widget? lease;
    if (grace) {
      lease = null;
    } else if (end != null) {
      final left = end.difference(now);
      if (left <= arnsRenewalNoticeWindow) {
        lease = ArNSTag(
          text: strings.arnsRenewsInDays(left.inDays.clamp(0, 30)),
          warning: true,
        );
      } else {
        lease = ArNSCaption(
          strings.arnsLeaseEnds(DateFormat.yMMMd().format(end.toLocal())),
        );
      }
    }

    final header = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: ArDriveSpacing.sm,
      runSpacing: ArDriveSpacing.xxs,
      children: [
        Text(
          arnsHostFor(name.name),
          style: typography.heading5(
            color: colors.textHigh,
            fontWeight: ArFontWeight.bold,
          ),
        ),
        if (name.role == ArNSRole.controller)
          ArNSTag(text: strings.arnsManagedForOwner),
        if (lease != null) lease,
        if (end != null && !grace)
          ArDriveLink(
            text: strings.arnsRenew,
            external: true,
            onTap: () => openUrl(url: arnsConsoleUrl),
          ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.containerRaised,
        borderRadius: BorderRadius.circular(ArDriveRadius.lg),
        border: Border.all(color: colors.strokeLow),
      ),
      padding: EdgeInsets.all(isPhone ? ArDriveSpacing.md : ArDriveSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          const SizedBox(height: ArDriveSpacing.xxs),
          ArNSCaption(
            name.hasFreeUndername
                ? strings.arnsUndernamesUsed(
                    name.undernamesUsed, name.undernameLimit)
                : strings.arnsAllUndernamesUsed(name.undernameLimit),
          ),
          if (grace) ...[
            const SizedBox(height: ArDriveSpacing.sm),
            ArDriveNotice(
              type: ArDriveNoticeType.warning,
              message: strings.arnsRenewInConsole,
              actionLabel: strings.arnsOpenConsole,
              onAction: () => openUrl(url: arnsConsoleUrl),
            ),
          ],
          const SizedBox(height: ArDriveSpacing.md),
          if (!isPhone) const _RecordHeadings(),
          for (final record in name.records)
            _RecordRow(
              isLast: identical(record, name.records.last),
              record: record,
              placeholder: placeholder,
              blocked: grace,
              isPhone: isPhone,
            ),
        ],
      ),
    );
  }
}

const _nameColumnFlex = 4;
const _pointsToColumnFlex = 5;
const _cacheColumnWidth = 96.0;

/// Wide enough for "Use this name" and Remove side by side.
const _actionsColumnWidth = 264.0;

class _RecordHeadings extends StatelessWidget {
  const _RecordHeadings();

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final style = typography.paragraphSmall(
      color: colors.textLow,
      fontWeight: ArFontWeight.semiBold,
    );
    return Container(
      padding: const EdgeInsets.only(bottom: ArDriveSpacing.xs),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.strokeLow)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: _nameColumnFlex,
            child: Text(strings.arnsName, style: style),
          ),
          Expanded(
            flex: _pointsToColumnFlex,
            child: Text(strings.arnsPointsTo, style: style),
          ),
          SizedBox(
            width: _cacheColumnWidth,
            child: Text(strings.arnsCacheTime, style: style),
          ),
          const SizedBox(width: _actionsColumnWidth),
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({
    required this.isLast,
    required this.record,
    required this.placeholder,
    required this.blocked,
    required this.isPhone,
  });

  final ArNSNameRecord record;
  final String? placeholder;
  final bool blocked;
  final bool isPhone;
  final bool isLast;

  bool get _unused =>
      placeholder != null && record.transactionId == placeholder;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    final host = Text(
      arnsHostFor(record.literalName),
      overflow: TextOverflow.ellipsis,
      style: typography.paragraphNormal(
        color: colors.textHigh,
        fontWeight: ArFontWeight.semiBold,
      ),
    );
    final pointsTo = _PointsToCell(record: record, placeholder: placeholder);
    final cacheTime = ArDriveLink(
      text: arnsTtlLabel(context, record.ttlSeconds),
      isAction: true,
      color: blocked ? colors.textLow : null,
      onTap: blocked
          ? null
          : () => showArNSNameDialog(
                context,
                mode: ArNSNameDialogMode.cacheTime,
                choice: _choice,
              ),
    );
    final actions = Wrap(
      alignment: isPhone ? WrapAlignment.start : WrapAlignment.end,
      spacing: ArDriveSpacing.xs,
      children: [
        ArDriveButtonNew(
          text: _unused ? strings.arnsUseThisName : strings.arnsChange,
          typography: typography,
          size: ArDriveButtonSize.compact,
          variant: _unused ? ButtonVariant.primary : ButtonVariant.secondary,
          isDisabled: blocked,
          onPressed: () => showArNSNameDialog(
            context,
            mode: ArNSNameDialogMode.pointRecord,
            choice: _choice,
          ),
        ),
        ArDriveButtonNew(
          text: strings.arnsRemove,
          typography: typography,
          size: ArDriveButtonSize.compact,
          variant: ButtonVariant.outline,
          isDisabled: blocked || (record.isApex && _unused),
          onPressed: () => _remove(context),
        ),
      ],
    );

    final divider = BoxDecoration(
      border:
          isLast ? null : Border(bottom: BorderSide(color: colors.strokeLow)),
    );

    if (isPhone) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: ArDriveSpacing.sm),
        decoration: divider,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            host,
            const SizedBox(height: ArDriveSpacing.xxs),
            pointsTo,
            const SizedBox(height: ArDriveSpacing.xxs),
            Row(
              children: [
                Text(
                  '${strings.arnsCacheTime}: ',
                  style: typography.paragraphSmall(color: colors.textLow),
                ),
                cacheTime,
              ],
            ),
            const SizedBox(height: ArDriveSpacing.xs),
            Align(alignment: Alignment.centerLeft, child: actions),
          ],
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: ArDriveSpacing.xs),
      decoration: divider,
      child: Row(
        children: [
          Expanded(flex: _nameColumnFlex, child: host),
          Expanded(flex: _pointsToColumnFlex, child: pointsTo),
          SizedBox(
            width: _cacheColumnWidth,
            child: Align(alignment: Alignment.centerLeft, child: cacheTime),
          ),
          SizedBox(width: _actionsColumnWidth, child: actions),
        ],
      ),
    );
  }

  ArNSRecordChoice get _choice =>
      ArNSRecordChoice(name: record.name, undername: record.undername);

  void _remove(BuildContext context) {
    final target = record.target;
    promptToRemoveArNSName(
      context,
      record: record,
      // The file whose metadata loses the name.
      item: target is ArNSFileItem && target.isLatestVersion
          ? ArNSNameableItem(
              fileId: target.fileId,
              driveId: target.driveId,
              name: target.name,
              dataTxId: record.transactionId,
              isManifest: target.isManifest,
            )
          : null,
    );
  }
}

/// The item, a link that opens it; or "Points elsewhere" and the ID.
class _PointsToCell extends StatelessWidget {
  const _PointsToCell({required this.record, required this.placeholder});

  final ArNSNameRecord record;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final target = record.target;
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final strings = appLocalizationsOf(context);
    if (target is ArNSFileItem &&
        (placeholder == null || record.transactionId != placeholder)) {
      return Row(
        children: [
          Icon(
            target.isManifest
                ? Icons.web_outlined
                : Icons.insert_drive_file_outlined,
            size: 16,
            color: colors.iconMid,
          ),
          const SizedBox(width: ArDriveSpacing.xs),
          Flexible(
            child: ArDriveLink(
              text: target.isLatestVersion
                  ? target.name
                  : strings.arnsOlderVersionOf(target.name),
              onTap: () => _open(context, target),
            ),
          ),
        ],
      );
    }
    return ArNSPointsTo(record: record, placeholder: placeholder);
  }

  void _open(BuildContext context, ArNSFileItem target) {
    context.read<AppRouterDelegate>().requestFolder(
          target.driveId,
          target.parentFolderId,
          itemId: target.fileId,
        );
    context.read<DrivesCubit>().selectDrive(target.driveId);
  }
}

/// Links an ArNS wallet from the Names page or the profile card.
Future<void> showArNSWalletDialog(
  BuildContext context, {
  bool changing = false,
}) {
  final strings = appLocalizationsOf(context);
  final walletCubit = context.read<ArNSWalletCubit>();
  final content = BlocProvider.value(
    value: walletCubit,
    child: Builder(
      builder: (dialogContext) => ArDriveStandardModalNew(
        title: changing
            ? strings.arnsChangeArNSWallet
            : strings.arnsLinkSolanaWallet,
        width: 440,
        scrollableContent: true,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ArNSBodyText(strings.arnsLinkWalletPageBody),
            const SizedBox(height: ArDriveSpacing.md),
            ArNSWalletChooser(
              changing: changing,
              onLinked: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        ),
        actions: [
          ModalAction.dismiss(
            title: strings.cancel,
            action: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    ),
  );
  if (MediaQuery.sizeOf(context).width < arnsSheetBreakpoint) {
    return showArDriveBottomSheet(
      context,
      builder: (_) => BlocProvider.value(
        value: walletCubit,
        child: Builder(
          builder: (sheetContext) => ArDriveBottomSheet(
            title: changing
                ? strings.arnsChangeArNSWallet
                : strings.arnsLinkSolanaWallet,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ArNSBodyText(strings.arnsLinkWalletPageBody),
                const SizedBox(height: ArDriveSpacing.md),
                ArNSWalletChooser(
                  changing: changing,
                  onLinked: () => Navigator.of(sheetContext).pop(),
                ),
              ],
            ),
            actions: [
              ModalAction.dismiss(
                title: strings.cancel,
                action: () => Navigator.of(sheetContext).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
  return showArDriveDialog(context, content: content);
}

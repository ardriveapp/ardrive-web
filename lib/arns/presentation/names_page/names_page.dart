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
import 'package:ardrive/components/copy_button.dart';
import 'package:ardrive/components/details_panel.dart';
import 'package:ardrive/components/list_page/list_page_layout.dart';
import 'package:ardrive/components/list_page/list_table.dart';
import 'package:ardrive/drives_list/presentation/open_drive_on_selection.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/format_date.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/size_constants.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// From 30 days before a lease ends, "Renews in 12 days".
const arnsRenewalNoticeWindow = Duration(days: 30);

/// The Names page in the app shell: a drive chosen in the sidebar opens it,
/// as on the drives list.
///
/// Reads the drives cubit in its own build. The router builds its shells
/// above the providers that hold that cubit, so reading it there threw and
/// the page never appeared.
class ArNSNamesShell extends StatelessWidget {
  const ArNSNamesShell({
    super.key,
    required this.onOpenDrive,
    this.child = const AppShell(page: ArNSNamesPage()),
  });

  final void Function(String driveId) onOpenDrive;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return OpenDriveOnSelection(
      selections: context.read<DrivesCubit>().driveSelections,
      onOpenDrive: onOpenDrive,
      child: child,
    );
  }
}

/// Names: every name the ArNS wallet owns or manages, in the list pages'
/// frame (docs/NAMES.md, "The Names page"). A click shows a name's details
/// beside the list, a double-click opens its page. Read from ArNS again each
/// time it opens.
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
    return const ListPageChrome(
      desktopChild: ArNSNamesBody(),
      child: ArNSNamesView(),
    );
  }
}

/// The names with one name's details beside them, as desktop shows it.
class ArNSNamesBody extends StatelessWidget {
  const ArNSNamesBody({super.key, this.initialChosenId});

  /// See [ListDetailsHost.initialChosenId].
  final String? initialChosenId;

  @override
  Widget build(BuildContext context) {
    final names = context.watch<ArNSNamesCubit>().state;
    return ListDetailsHost(
      initialChosenId: initialChosenId,
      buildBody: ({chosenId, onChoose}) =>
          ArNSNamesView(chosenId: chosenId, onChoose: onChoose),
      panelFor: (context, id, close) {
        final name = names.nameOf(id);
        if (name == null || name.isExpired(DateTime.now())) return null;
        return ArNSNameDetailsPanel(
          key: ValueKey('name-details-$id'),
          name: name,
          onClose: close,
        );
      },
    );
  }
}

enum ArNSNamesSort { name, leaseEnds }

/// The narrowest list that draws the names' columns; narrower, each name is
/// a stacked card.
const double arnsNamesColumnsFrom = 520;

bool _showsColumns(BuildContext context, double width) =>
    width - listRowHorizontalPadding * 2 - listMenuGutter >=
    arnsNamesColumnsFrom * MediaQuery.textScalerOf(context).scale(1);

/// The page's content under the top bar: the title row and the names.
class ArNSNamesView extends StatefulWidget {
  const ArNSNamesView({super.key, this.chosenId, this.onChoose});

  /// The name whose details are open beside the list, if any.
  final String? chosenId;

  /// A click on a row: show its details. Null where there is no room.
  final void Function(String name)? onChoose;

  @override
  State<ArNSNamesView> createState() => _ArNSNamesViewState();
}

class _ArNSNamesViewState extends State<ArNSNamesView> {
  ArNSNamesSort _sort = ArNSNamesSort.name;
  bool _ascending = true;

  void _sortBy(ArNSNamesSort column) => setState(() {
        if (_sort == column) {
          _ascending = !_ascending;
        } else {
          _sort = column;
          _ascending = true;
        }
      });

  List<ArNSManagedName> _sorted(List<ArNSManagedName> names) {
    // A name bought for good never ends: after every lease.
    final never = DateTime(9999);
    int compare(ArNSManagedName a, ArNSManagedName b) => switch (_sort) {
          ArNSNamesSort.name => a.name.compareTo(b.name),
          ArNSNamesSort.leaseEnds =>
            (a.endTimestamp ?? never).compareTo(b.endTimestamp ?? never),
        };
    return [...names]
      ..sort((a, b) => _ascending ? compare(a, b) : compare(b, a));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ArNSWalletCubit, ArNSWalletState>(
      builder: (context, wallet) => BlocBuilder<ArNSNamesCubit, ArNSNamesState>(
        builder: (context, names) => LayoutBuilder(
          builder: (context, constraints) {
            final showsColumns = _showsColumns(context, constraints.maxWidth);
            return ArDriveScrollBar(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _titleRow(context, wallet, names),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: listPageBlockGap),
                  ),
                  ..._body(context, wallet, names, showsColumns),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: listPageSectionGap),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _titleRow(
    BuildContext context,
    ArNSWalletState wallet,
    ArNSNamesState names,
  ) {
    final strings = appLocalizationsOf(context);
    return ListPageTitleRow(
      title: Row(
        children: [
          Flexible(child: ListPageTitleRow.text(context, strings.arnsNames)),
          if (names.refreshing && names.status == ArNSNamesStatus.loaded)
            const Padding(
              padding: EdgeInsets.only(left: ArDriveSpacing.sm),
              child: ArDriveSpinner(),
            ),
        ],
      ),
      action: wallet.linked == null
          ? null
          : _GetANameButton(label: strings.arnsGetAName),
    );
  }

  List<Widget> _body(
    BuildContext context,
    ArNSWalletState wallet,
    ArNSNamesState names,
    bool showsColumns,
  ) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    Widget box(Widget child) => SliverToBoxAdapter(child: child);
    Widget padded(Widget child) => box(Padding(
          padding: const EdgeInsets.fromLTRB(
            listPagePadding,
            0,
            listPagePadding,
            listPageBlockGap,
          ),
          child: child,
        ));

    if (wallet.linked == null) {
      return [
        box(ListPageMessage(
          child: ArDriveEmptyState(
            icon: Icon(arnsNameIcon, size: 32, color: colors.iconLow),
            title: strings.arnsLinkWalletTitle,
            message: strings.arnsLinkWalletPageBody,
            actionLabel: strings.arnsLinkSolanaWallet,
            onAction: () => showArNSWalletDialog(context),
            secondaryActionLabel: strings.arnsWhatIsArNS,
            onSecondaryAction: () => openUrl(url: arnsDocsUrl),
          ),
        )),
      ];
    }

    switch (names.status) {
      case ArNSNamesStatus.none:
      case ArNSNamesStatus.loading:
        return [
          box(const ListPageMessage(
            child: ArDriveSpinner(size: ArDriveSpinnerSize.large),
          )),
        ];
      case ArNSNamesStatus.failed:
        return [
          padded(ArDriveNotice(
            type: ArDriveNoticeType.error,
            message: strings.arnsNamesCouldNotBeRead,
            actionLabel: strings.tryAgain,
            onAction: () => context.read<ArNSNamesCubit>().refresh(),
          )),
        ];
      case ArNSNamesStatus.loaded:
        break;
    }

    final now = DateTime.now();
    final shown = _sorted([
      for (final name in names.names)
        if (!name.isExpired(now)) name,
    ]);
    if (shown.isEmpty) {
      return [box(const ListPageMessage(child: ArNSNoNames()))];
    }

    final rows = SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final name = shown[index];
          return ArNSNameRow(
            key: ValueKey(name.name),
            name: name,
            now: now,
            showsColumns: showsColumns,
            chosen:
                widget.onChoose == null ? null : widget.chosenId == name.name,
            onChoose: widget.onChoose == null
                ? null
                : () => widget.onChoose!(name.name),
          );
        },
        childCount: shown.length,
      ),
    );

    return [
      if (names.refreshFailed)
        padded(ArDriveNotice(
          type: ArDriveNoticeType.warning,
          message: strings.arnsShowingLastRead,
          actionLabel: strings.tryAgain,
          onAction: () => context.read<ArNSNamesCubit>().refresh(),
        )),
      if (showsColumns)
        ListTablePanel(
          header: ListTableHeader<ArNSNamesSort>(
            sort: _sort,
            sortAscending: _ascending,
            onSort: _sortBy,
            columns: [
              ListColumn(strings.arnsName, _nameFlex,
                  sortKey: ArNSNamesSort.name),
              ListColumn(strings.arnsUndernames, _undernamesFlex),
              ListColumn(strings.arnsLeaseEndsHeading, _leaseFlex,
                  sortKey: ArNSNamesSort.leaseEnds),
            ],
          ),
          rows: rows,
        )
      else
        rows,
    ];
  }
}

const _nameFlex = 5;
const _undernamesFlex = 3;
const _leaseFlex = 4;

/// When a name's lease ends: a date, red status text from
/// [arnsRenewalNoticeWindow] before ("Ends in 12 days") and in its grace
/// period ("Ended"), "Never" for a name bought for good.
class ArNSLeaseCell extends StatelessWidget {
  const ArNSLeaseCell({
    super.key,
    required this.name,
    required this.now,
    this.underHeading = true,
  });

  final ArNSManagedName name;
  final DateTime now;

  /// False on a stacked card, where no heading says what a bare date is:
  /// "Lease ends Jun 25, 2027".
  final bool underHeading;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final end = name.endTimestamp;
    if (end == null) return ListTextCell(strings.arnsLeaseNeverEnds);
    // A lease about to be lost is said in red, as status text, not boxed.
    Widget status(String text) => Align(
          alignment: AlignmentDirectional.centerStart,
          child: ArDriveStatusText(
            text: text,
            type: ArDriveStatusType.error,
            maxLines: 1,
          ),
        );
    if (name.isInGracePeriod(now)) return status(strings.arnsLeaseEnded);
    final left = end.difference(now);
    if (left <= arnsRenewalNoticeWindow) {
      final days = left.inDays.clamp(0, 30);
      // Under the Lease ends heading the short form; on a card, which has
      // no heading, the whole sentence.
      return status(
        underHeading
            ? strings.arnsEndsInDays(days)
            : strings.arnsLeaseEndsInDays(days),
      );
    }
    return ListTextCell(
      underHeading ? formatDate(end) : strings.arnsLeaseEnds(formatDate(end)),
    );
  }
}

/// A name needs renewing: within [arnsRenewalNoticeWindow] of its lease
/// ending, or in its grace period.
bool arnsNeedsRenewal(ArNSManagedName name, DateTime now) {
  final end = name.endTimestamp;
  return end != null && end.difference(now) <= arnsRenewalNoticeWindow;
}

/// One name, as a table row or a stacked card.
class ArNSNameRow extends StatelessWidget {
  const ArNSNameRow({
    super.key,
    required this.name,
    required this.now,
    required this.showsColumns,
    this.chosen,
    this.onChoose,
  });

  final ArNSManagedName name;
  final DateTime now;
  final bool showsColumns;
  final bool? chosen;
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final title = ListNameCell(
      icon: Icon(arnsNameIcon,
          size: ListNameCell.iconSize, color: colors.textMid),
      title: name.name,
    );
    final undernames = ListTextCell(
        strings.arnsUndernamesOf(name.undernamesUsed, name.undernameLimit));
    final lease = ArNSLeaseCell(name: name, now: now);

    return ListTableRow(
      semanticLabel: name.name,
      onOpen: () =>
          context.read<AppRouterDelegate>().showNames(name: name.name),
      showsColumns: showsColumns,
      chosen: chosen,
      onChoose: onChoose,
      menu: ArNSNameMenu(name: name),
      child: showsColumns
          ? ListColumnsRow(
              flexes: const [_nameFlex, _undernamesFlex, _leaseFlex],
              cells: [title, undernames, lease],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                title,
                const SizedBox(height: listStackedGap),
                ListTextCell(strings.arnsUndernamesUsed(
                    name.undernamesUsed, name.undernameLimit)),
                // A name bought for good has no lease to speak of.
                if (name.endTimestamp != null) ...[
                  const SizedBox(height: listStackedGap),
                  ArNSLeaseCell(name: name, now: now, underHeading: false),
                ],
              ],
            ),
    );
  }
}

/// A name's ⋮ menu: Open, Renew, Copy link.
class ArNSNameMenu extends StatelessWidget {
  const ArNSNameMenu({super.key, required this.name});

  final ArNSManagedName name;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    ArDriveDropdownItem item(String label, IconData icon, VoidCallback onTap) =>
        ArDriveDropdownItem(
          onClick: onTap,
          content: ArDriveDropdownItemTile(
            name: label,
            icon: ArDriveIcon(icon: icon, size: ListRowMenu.iconSize),
          ),
        );
    return ListRowMenu(
      label: strings.showMenu,
      items: [
        item(strings.listOpen, Icons.arrow_forward,
            () => context.read<AppRouterDelegate>().showNames(name: name.name)),
        if (name.endTimestamp != null)
          item(strings.arnsRenew, Icons.autorenew,
              () => openUrl(url: arnsRenewUrlFor(name.name))),
        item(
          strings.copyLink,
          Icons.link,
          () => Clipboard.setData(ClipboardData(text: arnsUrlFor(name.name))),
        ),
      ],
    );
  }
}

/// A name's details beside the Names list, in the file details panel's
/// shape: Open and, for a lease, Renew as icon buttons in the toolbar; then
/// the name; then when its lease ends, undernames used and its link, on the
/// file panel's label and value grid.
class ArNSNameDetailsPanel extends StatelessWidget {
  const ArNSNameDetailsPanel({
    super.key,
    required this.name,
    required this.onClose,
  });

  final ArNSManagedName name;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final now = DateTime.now();
    final host = arnsHostFor(name.name);
    void open() => context.read<AppRouterDelegate>().showNames(name: name.name);

    return ListDetailsPanel(
      onClose: onClose,
      icon: Icon(arnsNameIcon, size: 24, color: colors.textMid),
      title: host,
      toolbarActions: [
        DetailsPanelToolbarAction(
          tooltip: strings.listOpen,
          icon: const ArDriveIcon(
            icon: Icons.arrow_forward,
            size: defaultIconSize,
          ),
          onTap: open,
        ),
        if (name.endTimestamp != null)
          DetailsPanelToolbarAction(
            tooltip: strings.arnsRenew,
            // Red while the lease is about to be lost, as the date below
            // it is: the one action that cannot wait.
            icon: ArDriveIcon(
              icon: Icons.autorenew,
              size: defaultIconSize,
              color: arnsNeedsRenewal(name, now) ? colors.statusErrorFg : null,
            ),
            onTap: () => openUrl(url: arnsRenewUrlFor(name.name)),
          ),
      ],
      details: [
        // Said once, here, rather than as a tag on every row: a controller
        // signs its own changes and pays for them in SOL, so it is worth
        // knowing, but not worth repeating down the list.
        if (name.role == ArNSRole.controller)
          DetailsPanelItem(
            itemTitle: strings.arnsRoleHeading,
            leading: DetailsPanelValueText(strings.arnsController),
          ),
        DetailsPanelItem(
          itemTitle: strings.arnsLeaseEndsHeading,
          leading: _LeaseValue(name: name, now: now),
        ),
        DetailsPanelItem(
          itemTitle: strings.arnsUndernames,
          leading: DetailsPanelValueText(
            strings.arnsUndernamesOf(name.undernamesUsed, name.undernameLimit),
          ),
        ),
        DetailsPanelItem(
          itemTitle: strings.webPagesLink,
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: ArDriveLink(
                  // On the right, like every value in the panel, when it wraps.
                  textAlign: TextAlign.right,
                  text: host,
                  external: true,
                  onTap: () => openUrl(url: arnsUrlFor(name.name)),
                ),
              ),
              const SizedBox(width: 8),
              CopyButton(text: arnsUrlFor(name.name), size: 18),
            ],
          ),
        ),
      ],
    );
  }
}

/// When a lease ends, as a value in the panel: on the right like the rest,
/// in red while it is about to be lost. The table's [ArNSLeaseCell] holds
/// itself to the start of its column, which in the panel put it on the left
/// of every other value.
class _LeaseValue extends StatelessWidget {
  const _LeaseValue({required this.name, required this.now});

  final ArNSManagedName name;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final end = name.endTimestamp;
    if (end == null) return DetailsPanelValueText(strings.arnsLeaseNeverEnds);
    Widget status(String text) => ArDriveStatusText(
          text: text,
          type: ArDriveStatusType.error,
          maxLines: 1,
        );
    if (name.isInGracePeriod(now)) return status(strings.arnsLeaseEnded);
    final left = end.difference(now);
    if (left <= arnsRenewalNoticeWindow) {
      return status(strings.arnsEndsInDays(left.inDays.clamp(0, 30)));
    }
    return DetailsPanelValueText(formatDate(end));
  }
}

/// A name's records a page at a time: some names have dozens.
const arnsRecordsPerPage = 10;

/// The host, its tags: the title of the name's own page.
class _NameTitle extends StatelessWidget {
  const _NameTitle({required this.name, required this.now});

  final ArNSManagedName name;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final grace = name.isInGracePeriod(now);
    final end = name.endTimestamp;

    Widget? lease;
    if (!grace && end != null) {
      final left = end.difference(now);
      // About to be lost: said in red, not boxed (ardrive_ui's status text).
      lease = left <= arnsRenewalNoticeWindow
          ? ArDriveStatusText(
              text: strings.arnsLeaseEndsInDays(left.inDays.clamp(0, 30)),
              type: ArDriveStatusType.error,
            )
          : ArNSCaption(strings.arnsLeaseEnds(formatDate(end)));
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: ArDriveSpacing.sm,
      runSpacing: ArDriveSpacing.xxs,
      children: [
        ListPageTitleRow.text(context, arnsHostFor(name.name)),
        if (name.role == ArNSRole.controller)
          ArDriveTag(text: strings.arnsController),
        if (lease != null) lease,
      ],
    );
  }
}

/// [records] whose literal name (`blog_ardrive`) has [query] in it.
List<ArNSNameRecord> arnsRecordsMatching(
  List<ArNSNameRecord> records,
  String query,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return records;
  return [
    for (final r in records)
      if (r.literalName.toLowerCase().contains(needle)) r,
  ];
}

/// A record on its name's own page: the undername alone, or the bare name
/// for the name itself.
String arnsShortLabel(ArNSNameRecord record) =>
    record.isApex ? record.name : record.undername;

/// One name's page: its records, with a search over them (docs/NAMES.md,
/// "The Names page"). Opened from the Names list or the nav.
class ArNSNamePage extends StatefulWidget {
  const ArNSNamePage({super.key, required this.name});

  final String name;

  @override
  State<ArNSNamePage> createState() => _ArNSNamePageState();
}

class _ArNSNamePageState extends State<ArNSNamePage> {
  @override
  void initState() {
    super.initState();
    context.read<ArNSNamesCubit>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListPageChrome(child: ArNSNameView(name: widget.name));
  }
}

/// One name's page under the top bar: the way back, the title row, the
/// search and the records.
///
/// A click on a record only highlights it - its details are its row - and a
/// double-click opens its link, the full URL.
class ArNSNameView extends StatefulWidget {
  const ArNSNameView({super.key, required this.name});

  final String name;

  @override
  State<ArNSNameView> createState() => _ArNSNameViewState();
}

class _ArNSNameViewState extends State<ArNSNameView> {
  String _query = '';
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    Widget padded(Widget child, {double bottom = listPageBlockGap}) =>
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              listPagePadding,
              0,
              listPagePadding,
              bottom,
            ),
            child: child,
          ),
        );
    final back = SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          listPagePadding,
          ArDriveSpacing.sm,
          listPagePadding,
          0,
        ),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: ArDriveLink(
            text: strings.arnsNames,
            onTap: () => context.read<AppRouterDelegate>().showNames(),
          ),
        ),
      ),
    );

    return BlocBuilder<ArNSNamesCubit, ArNSNamesState>(
      builder: (context, names) => LayoutBuilder(
        builder: (context, constraints) {
          final now = DateTime.now();
          final name = names.nameOf(widget.name);
          final List<Widget> body;
          if (name == null || name.isExpired(now)) {
            final settled = names.status == ArNSNamesStatus.loaded ||
                names.status == ArNSNamesStatus.none;
            final failed = names.status == ArNSNamesStatus.failed;
            body = [
              SliverToBoxAdapter(
                child: ListPageTitleRow(
                  title: ListPageTitleRow.text(
                    context,
                    arnsHostFor(widget.name),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                // A read that failed says so, as the Names list does, rather
                // than spinning with nothing on the way.
                child: failed
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: listPagePadding),
                        child: ArDriveNotice(
                          type: ArDriveNoticeType.error,
                          message: strings.arnsNamesCouldNotBeRead,
                          actionLabel: strings.tryAgain,
                          onAction: () =>
                              context.read<ArNSNamesCubit>().refresh(),
                        ),
                      )
                    : ListPageMessage(
                        child: settled
                            ? ArNSBodyText(strings.arnsNameNotFound)
                            : const ArDriveSpinner(
                                size: ArDriveSpinnerSize.large),
                      ),
              ),
            ];
          } else {
            final showsColumns = constraints.maxWidth - listMenuGutter >= 560;
            final grace = name.isInGracePeriod(now);
            final records = arnsRecordsMatching(name.records, _query);
            final pages = (records.length / arnsRecordsPerPage).ceil();
            // A removed record can leave the page past the end.
            final page = _page.clamp(0, pages == 0 ? 0 : pages - 1);
            final start = page * arnsRecordsPerPage;
            final shown = records.skip(start).take(arnsRecordsPerPage).toList();
            final placeholder =
                context.read<ConfigService>().config.arnsPlaceholderTxId;
            final rows = SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => ArNSRecordRow(
                  key: ValueKey(shown[index].undername),
                  record: shown[index],
                  placeholder: placeholder,
                  blocked: grace,
                  showsColumns: showsColumns,
                ),
                childCount: shown.length,
              ),
            );

            body = [
              SliverToBoxAdapter(
                child: ListPageTitleRow(
                  title: _NameTitle(name: name, now: now),
                  action: name.endTimestamp != null && !grace
                      ? ArDriveButtonNew(
                          text: strings.arnsRenew,
                          typography: typography,
                          variant: arnsNeedsRenewal(name, now)
                              ? ButtonVariant.primary
                              : ButtonVariant.secondary,
                          maxWidth: ArDriveButtonNew.fittedWidth(
                            context,
                            strings.arnsRenew,
                            minWidth: 96,
                          ),
                          onPressed: () =>
                              openUrl(url: arnsRenewUrlFor(name.name)),
                        )
                      : null,
                ),
              ),
              padded(_NameSummary(name: name, now: now)),
              padded(
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SizedBox(
                    width: showsColumns ? 360 : double.infinity,
                    child: ArDriveTextFieldNew(
                      hintText: strings.arnsFindUndername,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      onChanged: (query) => setState(() {
                        _query = query;
                        // A new search starts from its first match.
                        _page = 0;
                      }),
                    ),
                  ),
                ),
              ),
              if (records.isEmpty)
                padded(ArNSCaption(strings.arnsNoUndernamesMatch))
              else ...[
                if (showsColumns)
                  ListTablePanel(
                    header: ListTableHeader<Never>(
                      columns: [
                        ListColumn(strings.arnsName, _recordNameFlex),
                        ListColumn(strings.arnsPointsTo, _pointsToFlex),
                        ListColumn(strings.arnsCacheTime, _cacheFlex),
                      ],
                    ),
                    rows: rows,
                  )
                else
                  rows,
                if (pages > 1)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        listPagePadding,
                        ArDriveSpacing.sm,
                        listPagePadding,
                        0,
                      ),
                      child: _Pager(
                        from: start + 1,
                        to: start + shown.length,
                        total: records.length,
                        onPrevious: page > 0
                            ? () => setState(() => _page = page - 1)
                            : null,
                        onNext: page < pages - 1
                            ? () => setState(() => _page = page + 1)
                            : null,
                      ),
                    ),
                  ),
              ],
            ];
          }

          return ArDriveScrollBar(
            child: CustomScrollView(
              slivers: [
                back,
                ...body,
                const SliverToBoxAdapter(
                  child: SizedBox(height: listPageSectionGap),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Undernames used, and the notice that changes wait for a renewal.
class _NameSummary extends StatelessWidget {
  const _NameSummary({required this.name, required this.now});

  final ArNSManagedName name;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ArNSCaption(
          name.hasFreeUndername
              ? strings.arnsUndernamesUsed(
                  name.undernamesUsed, name.undernameLimit)
              : strings.arnsAllUndernamesUsed(name.undernameLimit),
        ),
        if (name.isInGracePeriod(now)) ...[
          const SizedBox(height: ArDriveSpacing.sm),
          ArDriveNotice(
            type: ArDriveNoticeType.warning,
            message: strings.arnsRenewInConsole,
            actionLabel: strings.arnsRenew,
            onAction: () => openUrl(url: arnsRenewUrlFor(name.name)),
          ),
        ],
      ],
    );
  }
}

const _recordNameFlex = 4;
const _pointsToFlex = 5;
const _cacheFlex = 2;

/// One record on its name's page: the undername alone (`project-1`, or the
/// bare name for the name itself), what it points to and its cache time.
/// Copy link and opening still use the full URL.
class ArNSRecordRow extends StatelessWidget {
  const ArNSRecordRow({
    super.key,
    required this.record,
    required this.placeholder,
    required this.blocked,
    required this.showsColumns,
  });

  final ArNSNameRecord record;
  final String? placeholder;
  final bool blocked;
  final bool showsColumns;

  bool get _unused =>
      placeholder != null && record.transactionId == placeholder;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final label = ListNameCell(
      icon: Icon(
        record.isApex ? arnsNameIcon : Icons.subdirectory_arrow_right,
        size: ListNameCell.iconSize,
        color: colors.textMid,
      ),
      title: arnsShortLabel(record),
    );
    final pointsTo = _PointsToCell(record: record, placeholder: placeholder);
    final cacheTime = ListTextCell(arnsTtlLabel(context, record.ttlSeconds));
    // An unused name gets a quiet way in: the page's one primary action
    // stays Renew.
    final use = _unused && !blocked
        ? ArDriveLink(
            text: strings.arnsUseThisName,
            isAction: true,
            onTap: () => showArNSNameDialog(
              context,
              mode: ArNSNameDialogMode.pointRecord,
              choice: ArNSRecordChoice(
                name: record.name,
                undername: record.undername,
              ),
            ),
          )
        : null;

    return ListTableRow(
      semanticLabel: arnsHostFor(record.literalName),
      onOpen: () => openUrl(url: arnsUrlFor(record.literalName)),
      showsColumns: showsColumns,
      menu: ArNSRecordMenu(record: record, blocked: blocked, unused: _unused),
      child: showsColumns
          ? ListColumnsRow(
              flexes: const [_recordNameFlex, _pointsToFlex, _cacheFlex],
              cells: [
                label,
                use == null
                    ? pointsTo
                    : Wrap(
                        spacing: ArDriveSpacing.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [pointsTo, use],
                      ),
                cacheTime,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                label,
                const SizedBox(height: listStackedGap),
                pointsTo,
                const SizedBox(height: listStackedGap),
                ListTextCell(
                  strings.arnsCacheTimeIs(
                      arnsTtlLabel(context, record.ttlSeconds)),
                ),
                if (use != null) ...[
                  const SizedBox(height: listStackedGap),
                  use,
                ],
              ],
            ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.from,
    required this.to,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  final int from;
  final int to;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    Widget arrow(IconData icon, String tooltip, VoidCallback? onPressed) =>
        ArDriveIconButton(
          icon: ArDriveIcon(
            icon: icon,
            size: 20,
            color: onPressed == null ? colors.iconLow : colors.iconMid,
          ),
          tooltip: tooltip,
          onPressed: onPressed,
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          strings.arnsRecordsShown(from, to, total),
          style: typography.paragraphSmall(color: colors.textMid),
        ),
        const SizedBox(width: ArDriveSpacing.sm),
        arrow(Icons.chevron_left, strings.arnsPreviousPage, onPrevious),
        arrow(Icons.chevron_right, strings.arnsNextPage, onNext),
      ],
    );
  }
}

/// The item, a link that opens it; or "Points elsewhere".
class _PointsToCell extends StatelessWidget {
  const _PointsToCell({required this.record, required this.placeholder});

  final ArNSNameRecord record;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final target = record.target;
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final strings = appLocalizationsOf(context);
    final kind = arnsPointsToKind(record, placeholder: placeholder);
    if (target is ArNSFileItem &&
        (kind == ArNSPointsToKind.file ||
            kind == ArNSPointsToKind.olderVersion)) {
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

/// Links an ArNS wallet from the Names page or Account and security.
Future<void> showArNSWalletDialog(BuildContext context) {
  final strings = appLocalizationsOf(context);
  final walletCubit = context.read<ArNSWalletCubit>();
  final content = BlocProvider.value(
    value: walletCubit,
    child: Builder(
      builder: (dialogContext) => ArDriveStandardModalNew(
        title: strings.arnsLinkSolanaWallet,
        width: 440,
        scrollableContent: true,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ArNSBodyText(strings.arnsLinkWalletPageBody),
            const SizedBox(height: ArDriveSpacing.xs),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ArDriveLink(
                text: strings.arnsWhatIsArNS,
                external: true,
                onTap: () => openUrl(url: arnsDocsUrl),
              ),
            ),
            const SizedBox(height: ArDriveSpacing.md),
            ArNSWalletChooser(
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
            closeLabel: strings.close,
            title: strings.arnsLinkSolanaWallet,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ArNSBodyText(strings.arnsLinkWalletPageBody),
                const SizedBox(height: ArDriveSpacing.xs),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ArDriveLink(
                    text: strings.arnsWhatIsArNS,
                    external: true,
                    onTap: () => openUrl(url: arnsDocsUrl),
                  ),
                ),
                const SizedBox(height: ArDriveSpacing.md),
                ArNSWalletChooser(
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

/// One record's actions, the explorer's row menu pattern: Change, Change
/// cache time, Copy link, Remove.
class ArNSRecordMenu extends StatelessWidget {
  const ArNSRecordMenu({
    super.key,
    required this.record,
    required this.blocked,
    required this.unused,
  });

  final ArNSNameRecord record;

  /// In its grace period: nothing can change.
  final bool blocked;

  /// Pointing at "Nothing published here".
  final bool unused;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final height =
        MediaQuery.sizeOf(context).width < arnsSheetBreakpoint ? 44.0 : 48.0;
    final choice =
        ArNSRecordChoice(name: record.name, undername: record.undername);

    ArDriveDropdownItem item(
      String label,
      IconData icon,
      VoidCallback onTap, {
      bool enabled = true,
    }) =>
        ArDriveDropdownItem(
          onClick: enabled ? onTap : null,
          content: ArDriveDropdownItemTile(
            name: label,
            icon: ArDriveIcon(icon: icon, size: ListRowMenu.iconSize),
            isDisabled: !enabled,
            height: height,
          ),
        );

    final items = [
      item(
        unused ? strings.arnsUseThisName : strings.arnsChange,
        Icons.edit_outlined,
        () => showArNSNameDialog(
          context,
          mode: ArNSNameDialogMode.pointRecord,
          choice: choice,
        ),
        enabled: !blocked,
      ),
      item(
        strings.arnsChangeCacheTime,
        Icons.schedule,
        () => showArNSNameDialog(
          context,
          mode: ArNSNameDialogMode.cacheTime,
          choice: choice,
        ),
        enabled: !blocked,
      ),
      item(
        strings.copyLink,
        Icons.link,
        () => Clipboard.setData(
          ClipboardData(text: arnsUrlFor(record.literalName)),
        ),
      ),
      item(
        strings.arnsRemove,
        Icons.link_off,
        () => _remove(context),
        enabled: !blocked && !(record.isApex && unused),
      ),
    ];

    return ListRowMenu(label: strings.showMenu, items: items);
  }

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

/// Opens the ar.io Console, so the label carries the new-window icon after
/// it, as [ArDriveLink] does for an external link.
class _GetANameButton extends StatelessWidget {
  const _GetANameButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final style = typography.paragraphLarge(
      color: colors.textLink,
      fontWeight: ArFontWeight.semiBold,
    );
    final iconSize = (style.fontSize ?? 16) * 1.1;
    final iconWidth = MediaQuery.textScalerOf(context).scale(iconSize);
    return ArDriveButtonNew(
      text: label,
      typography: typography,
      variant: ButtonVariant.secondary,
      maxWidth: ArDriveButtonNew.fittedWidth(context, label, minWidth: 96) +
          (ArDriveSpacing.xxs + iconWidth).ceilToDouble(),
      customContent: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // As ArDriveButtonNew's own label, so this one sits where theirs
              // does rather than about 2 px low.
              textHeightBehavior: const TextHeightBehavior(
                applyHeightToFirstAscent: false,
                applyHeightToLastDescent: false,
              ),
              style: style,
            ),
          ),
          const SizedBox(width: ArDriveSpacing.xxs),
          ArDriveIcons.newWindow(size: iconSize, color: colors.textLink),
        ],
      ),
      onPressed: () => openUrl(url: arnsGetNameUrl),
    );
  }
}

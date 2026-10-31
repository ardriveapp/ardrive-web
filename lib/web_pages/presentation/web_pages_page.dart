import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/publication/domain/file_page.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/app_shell.dart';
import 'package:ardrive/arns/domain/arns_nameable_item.dart';
import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/presentation/item/arns_item_names.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog_cubit.dart';
import 'package:ardrive/arns/presentation/names/arns_names_cubit.dart';
import 'package:ardrive/arns/presentation/widgets/arns_widgets.dart';
import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/components/copy_button.dart';
import 'package:ardrive/components/details_panel.dart';
import 'package:ardrive/components/list_page/list_page_layout.dart';
import 'package:ardrive/components/list_page/list_table.dart';
import 'package:ardrive/drives_list/domain/drive_scope.dart';
import 'package:ardrive/drives_list/presentation/open_drive_on_selection.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart'
    show getIconForContentType;
import 'package:ardrive/publication/presentation/publish_to_web.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/format_date.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/size_constants.dart';
import 'package:ardrive/web_pages/domain/web_page.dart';
import 'package:ardrive/web_pages/presentation/web_pages_cubit.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The Web pages page in the app shell: a drive chosen in the sidebar opens
/// it, as on the Names page.
class WebPagesShell extends StatelessWidget {
  const WebPagesShell({
    super.key,
    required this.onOpenDrive,
    this.child = const AppShell(page: WebPagesPage()),
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

/// Shows where [page] lives in the drive explorer, the deployment picked
/// out of its folder.
///
/// From the explorer, on the drive already open, the explorer is told
/// directly: selecting that drive again changes nothing. Everywhere else
/// the folder is asked for before the selection that carries it, as the
/// Names page does.
void openWebPageFolder(BuildContext context, WebPage page) {
  final router = context.read<AppRouterDelegate>();
  final drives = context.read<DrivesCubit>();
  final drivesState = drives.state;
  final itemId = page.isDeployment
      ? page.id
      : page.isFilePage
          ? page.publication?.scope.fileIdOrNull
          : null;
  final inExplorer = !router.showingDrivesList &&
      !router.showingNames &&
      !router.showingWebPages;
  if (inExplorer &&
      drivesState is DrivesLoadSuccess &&
      drivesState.selectedDriveId == page.driveId) {
    context.read<DriveDetailCubit>().openFolder(
          folderId: page.openFolderId,
          selectedItemId: itemId,
        );
    return;
  }
  router.requestFolder(page.driveId, page.openFolderId, itemId: itemId);
  drives.selectDrive(page.driveId);
}

/// [page]'s link, from the user's names and the app's gateways.
WebPageLink webPageLink(BuildContext context, WebPage page) {
  // Names are read only where they are on: the cubit is not offered
  // anywhere else.
  final names = arnsNamesOn(context)
      ? context.watch<ArNSNamesCubit>().state.names
      : const <ArNSManagedName>[];
  final config = context.read<ConfigService>().config;
  return webPageLinkFor(
    page,
    names: names,
    publicationGatewayUrl: config.publicationGatewayUrl,
    dataGatewayUrl: config.arweaveGatewayForDataRequest.url,
  );
}

/// What the user has published, in the list pages' frame: a click shows a
/// page's details beside the list, a double-click opens the page.
class WebPagesPage extends StatelessWidget {
  const WebPagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ListPageChrome(
      desktopChild: WebPagesBody(),
      child: WebPagesView(),
    );
  }
}

/// The list with a page's details beside it, as desktop shows it.
class WebPagesBody extends StatelessWidget {
  const WebPagesBody({super.key, this.initialChosenId});

  /// See [ListDetailsHost.initialChosenId].
  final String? initialChosenId;

  @override
  Widget build(BuildContext context) {
    final pages = context.watch<WebPagesCubit>().state.pages;
    return ListDetailsHost(
      initialChosenId: initialChosenId,
      buildBody: ({chosenId, onChoose}) =>
          WebPagesView(chosenId: chosenId, onChoose: onChoose),
      panelFor: (context, id, close) {
        for (final page in pages) {
          if (page.id == id) {
            return WebPageDetailsPanel(
              key: ValueKey('web-page-details-$id'),
              page: page,
              onClose: close,
            );
          }
        }
        return null;
      },
    );
  }
}

enum WebPagesSort { name, updated }

/// The narrowest list that draws the three columns; narrower, each page is a
/// stacked card.
const double webPagesColumnsFrom = 600;

/// The page's content under the top bar: the title row and the list.
class WebPagesView extends StatefulWidget {
  const WebPagesView({super.key, this.chosenId, this.onChoose});

  /// The page whose details are open beside the list, if any.
  final String? chosenId;

  /// A click on a row: show its details. Null where there is no room for
  /// them.
  final void Function(String id)? onChoose;

  @override
  State<WebPagesView> createState() => _WebPagesViewState();
}

class _WebPagesViewState extends State<WebPagesView> {
  // Most recently updated first, as the nav lists them.
  WebPagesSort _sort = WebPagesSort.updated;
  bool _ascending = false;

  void _sortBy(WebPagesSort column) => setState(() {
        if (_sort == column) {
          _ascending = !_ascending;
        } else {
          _sort = column;
          // Names read A to Z; dates newest first.
          _ascending = column == WebPagesSort.name;
        }
      });

  List<WebPage> _sorted(List<WebPage> pages) {
    final sorted = [...pages];
    int compare(WebPage a, WebPage b) => switch (_sort) {
          WebPagesSort.name =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          WebPagesSort.updated => a.updatedAt.compareTo(b.updatedAt),
        };
    sorted.sort((a, b) => _ascending ? compare(a, b) : compare(b, a));
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final state = context.watch<WebPagesCubit>().state;
    final drivesKnown = context.watch<DrivesCubit>().state is DrivesLoadSuccess;

    void goToPublicDrives() => context
        .read<AppRouterDelegate>()
        .showDrivesList(scope: DriveScope.public);

    final titleRow = ListPageTitleRow(
      title: ListPageTitleRow.text(context, strings.webPages),
      // Secondary, like Names' "Get a name": red stays the New button's.
      action: ArDriveButtonNew(
        text: strings.webPagesPublish,
        typography: typography,
        variant: ButtonVariant.secondary,
        maxWidth: ArDriveButtonNew.fittedWidth(
          context,
          strings.webPagesPublish,
          minWidth: 96,
        ),
        // Choose what to publish, then publish it as its own menu does.
        // Not before the drives are known: the picker would say there are
        // none.
        isDisabled: !drivesKnown,
        onPressed: () => pickAndPublishToWeb(context),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final showsColumns = constraints.maxWidth -
                listRowHorizontalPadding * 2 -
                listMenuGutter >=
            webPagesColumnsFrom * MediaQuery.textScalerOf(context).scale(1);

        Widget failedNotice() => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  listPagePadding,
                  0,
                  listPagePadding,
                  listPageBlockGap,
                ),
                child: ArDriveNotice(
                  type: ArDriveNoticeType.error,
                  message: strings.webPagesCouldNotBeRead,
                  actionLabel: strings.tryAgain,
                  onAction: () => context.read<WebPagesCubit>().retry(),
                ),
              ),
            );

        final List<Widget> body;
        if (!state.loaded) {
          body = const [
            SliverToBoxAdapter(
              child: ListPageMessage(
                child: ArDriveSpinner(size: ArDriveSpinnerSize.large),
              ),
            ),
          ];
        } else if (state.failed && state.pages.isEmpty) {
          body = [failedNotice()];
        } else if (state.pages.isEmpty) {
          body = [
            SliverToBoxAdapter(
              child: ListPageMessage(
                child: ArDriveEmptyState(
                  icon: ArDriveIcons.publishToWeb(),
                  title: strings.webPagesNothingYet,
                  message: strings.webPagesNothingYetBody,
                  actionLabel: strings.webPagesGoToDrives,
                  onAction: goToPublicDrives,
                ),
              ),
            ),
          ];
        } else {
          final pages = _sorted(state.pages);
          final rows = SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final page = pages[index];
                return WebPageRow(
                  key: ValueKey(page.id),
                  page: page,
                  link: webPageLink(context, page),
                  showsColumns: showsColumns,
                  chosen: widget.onChoose == null
                      ? null
                      : widget.chosenId == page.id,
                  onChoose: widget.onChoose == null
                      ? null
                      : () => widget.onChoose!(page.id),
                );
              },
              childCount: pages.length,
            ),
          );
          body = [
            // Deployments are local; publications are not, and are missing.
            if (state.failed) failedNotice(),
            if (showsColumns)
              ListTablePanel(
                header: ListTableHeader<WebPagesSort>(
                  sort: _sort,
                  sortAscending: _ascending,
                  onSort: _sortBy,
                  columns: [
                    ListColumn(strings.webPagesPage, _pageFlex,
                        sortKey: WebPagesSort.name),
                    ListColumn(strings.webPagesLink, _linkFlex),
                    ListColumn(strings.webPagesUpdated, _updatedFlex,
                        sortKey: WebPagesSort.updated),
                  ],
                ),
                rows: rows,
              )
            else
              rows,
          ];
        }

        return ArDriveScrollBar(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: titleRow),
              const SliverToBoxAdapter(
                child: SizedBox(height: listPageBlockGap),
              ),
              ...body,
              const SliverToBoxAdapter(
                child: SizedBox(height: listPageSectionGap),
              ),
            ],
          ),
        );
      },
    );
  }
}

const _pageFlex = 6;
const _linkFlex = 5;
const _updatedFlex = 3;

/// A web page's icon, from what it publishes, as the explorer draws it: a
/// file page has its file's type icon (an image's for a .png), a drive's or
/// a folder's page the drive or folder icon. A deployment is a site, and its
/// icon says so to a screen reader too, where a tag beside the name used to.
Widget webPageIcon(BuildContext context, WebPage page, {double size = 20}) {
  final color = ArDriveTheme.of(context).themeData.colorTokens.textMid;
  if (page.isDeployment) {
    return Icon(
      Icons.web_outlined,
      size: size,
      color: color,
      semanticLabel: appLocalizationsOf(context).arnsDeployment,
    );
  }
  // The explorer's icon for the type, in the row's colour: the helper drops
  // the colour for most file types.
  ArDriveIcon typeIcon(String contentType) => ArDriveIcon(
        icon: getIconForContentType(contentType).icon,
        size: size,
        color: color,
      );
  if (page.isFilePage) {
    return Semantics(
      label: appLocalizationsOf(context).publishHowPage,
      child: typeIcon(page.contentType ?? ''),
    );
  }
  return typeIcon(page.isDrivePublication ? 'drive' : 'folder');
}

/// "<folder> in <drive>", or the drive's name alone. No "drive" or
/// "folder" suffix: names often end in one already ("New Test Drive drive").
String webPageSource(BuildContext context, WebPage page) {
  final strings = appLocalizationsOf(context);
  final folder = page.folderName;
  return folder == null
      ? page.driveName
      : strings.webPagesFromFolder(folder, page.driveName);
}

/// One web page, as a table row or a stacked card.
class WebPageRow extends StatelessWidget {
  const WebPageRow({
    super.key,
    required this.page,
    required this.link,
    required this.showsColumns,
    this.chosen,
    this.onChoose,
  });

  final WebPage page;
  final WebPageLink link;
  final bool showsColumns;
  final bool? chosen;
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final name = ListNameCell(
      icon: webPageIcon(context, page),
      title: page.title,
      subtitle: webPageSource(context, page),
    );
    final updated = formatDate(page.updatedAt);

    return ListTableRow(
      semanticLabel: page.title,
      onOpen: () => _WebPageActions(context, page, link).open(),
      showsColumns: showsColumns,
      chosen: chosen,
      onChoose: onChoose,
      menu: WebPageMenu(page: page, link: link),
      child: showsColumns
          ? ListColumnsRow(
              flexes: const [_pageFlex, _linkFlex, _updatedFlex],
              cells: [
                name,
                ListTextCell(link.label),
                ListTextCell(updated),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                name,
                const SizedBox(height: listStackedGap),
                ListTextCell(link.label),
                const SizedBox(height: listStackedGap),
                ListTextCell(strings.webPagesUpdatedOn(updated)),
              ],
            ),
    );
  }
}

/// A web page's actions, for its row's menu and its details panel.
class _WebPageActions {
  _WebPageActions(this.context, this.page, this.link);

  final BuildContext context;
  final WebPage page;
  final WebPageLink link;

  /// The link to open or copy: a private file page's carries the file's
  /// key, for its owner.
  Future<String> _url() async {
    // Only a private file page's link carries a key.
    if (!page.isPrivate) return link.url;
    final fileId = page.publication?.scope.fileIdOrNull;
    if (fileId == null) return link.url;
    return withFileKey(
      link.url,
      await fileKeyForLink(
        context.read<DriveDao>(),
        context.read<ProfileCubit>().state,
        driveId: page.driveId,
        fileId: fileId,
      ),
    );
  }

  Future<void> open() async => openUrl(url: await _url());

  Future<void> copyLink() async {
    final url = await _url();
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      showArDriveToast(
        messenger,
        text: appLocalizationsOf(context).webPagesLinkCopied,
        type: ArDriveStatusType.success,
        duration: const Duration(seconds: 3),
      );
    }
  }

  bool get canUpdate => page.publication != null;

  /// The published view, as Publish to web opens it, with Update in it.
  Future<void> update() async {
    final drive = await context
        .read<DriveDao>()
        .driveById(driveId: page.driveId)
        .getSingleOrNull();
    if (drive == null || !context.mounted) return;
    await openPublishToWeb(
      context,
      drive: drive,
      folderId: page.publication?.scope.folderIdOrNull,
      fileId: page.publication?.scope.fileIdOrNull,
    );
  }

  bool get canName => arnsNamesOn(context);

  String get nameLabel => link.arnsRecord == null
      ? appLocalizationsOf(context).arnsAddName
      : appLocalizationsOf(context).arnsChangeName;

  void name() => showArNSNameDialog(
        context,
        mode: ArNSNameDialogMode.nameItem,
        item: page.isDeployment
            ? ArNSNameableItem(
                fileId: page.id,
                driveId: page.driveId,
                name: page.title,
                dataTxId: page.dataTxId,
                isManifest: true,
              )
            : ArNSNameableItem.publication(
                publicationId: page.id,
                driveId: page.driveId,
                name: page.title,
                dataTxId: page.dataTxId,
              ),
      );

  void openFolder() => openWebPageFolder(context, page);
}

/// A page's ⋮ menu: Open page, Copy link, Update page, Add or Change name,
/// Open folder.
class WebPageMenu extends StatelessWidget {
  const WebPageMenu({super.key, required this.page, required this.link});

  final WebPage page;
  final WebPageLink link;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final actions = _WebPageActions(context, page, link);

    ArDriveDropdownItem item(
            String label, ArDriveIcon icon, VoidCallback onTap) =>
        ArDriveDropdownItem(
          onClick: onTap,
          content: ArDriveDropdownItemTile(name: label, icon: icon),
        );
    ArDriveIcon icon(IconData data) =>
        ArDriveIcon(icon: data, size: ListRowMenu.iconSize);

    return ListRowMenu(
      label: strings.showMenu,
      items: [
        item(strings.publishOpenPage, icon(Icons.open_in_new), actions.open),
        item(strings.copyLink, icon(Icons.link), actions.copyLink),
        if (actions.canUpdate)
          item(
            strings.webPagesUpdatePage,
            publishToWebIcon(size: ListRowMenu.iconSize),
            actions.update,
          ),
        if (actions.canName)
          item(actions.nameLabel, icon(arnsNameIcon), actions.name),
        item(strings.webPagesOpenFolder, icon(Icons.folder_open_outlined),
            actions.openFolder),
      ],
    );
  }
}

/// A web page's details beside the list, in the file details panel's
/// shape: its actions as icon buttons in the toolbar, in the row menu's
/// order, then its name, then its link with copy, where it comes from and
/// when it changed.
class WebPageDetailsPanel extends StatelessWidget {
  const WebPageDetailsPanel({
    super.key,
    required this.page,
    required this.onClose,
  });

  final WebPage page;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final link = webPageLink(context, page);
    final actions = _WebPageActions(context, page, link);

    ArDriveIcon icon(IconData data) =>
        ArDriveIcon(icon: data, size: defaultIconSize);

    return ListDetailsPanel(
      onClose: onClose,
      icon: webPageIcon(context, page, size: 24),
      title: page.title,
      toolbarActions: [
        DetailsPanelToolbarAction(
          tooltip: strings.publishOpenPage,
          icon: icon(Icons.open_in_new),
          onTap: actions.open,
        ),
        if (actions.canUpdate)
          DetailsPanelToolbarAction(
            tooltip: strings.webPagesUpdatePage,
            icon: publishToWebIcon(size: defaultIconSize),
            onTap: actions.update,
          ),
        if (actions.canName)
          DetailsPanelToolbarAction(
            tooltip: actions.nameLabel,
            icon: icon(arnsNameIcon),
            onTap: actions.name,
          ),
        DetailsPanelToolbarAction(
          tooltip: strings.webPagesOpenFolder,
          icon: icon(Icons.folder_open_outlined),
          onTap: actions.openFolder,
        ),
      ],
      details: [
        DetailsPanelItem(
          itemTitle: strings.webPagesLink,
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: ArDriveLink(
                  // On the right, like every value in the panel, when it wraps.
                  textAlign: TextAlign.right,
                  text: link.label,
                  external: true,
                  onTap: actions.open,
                ),
              ),
              const SizedBox(width: 8),
              // A private file page's link carries its key, worked out when
              // it is copied.
              if (page.isPrivate)
                ArDriveIconButton(
                  tooltip: strings.copyLink,
                  icon: ArDriveIcons.copy(size: 18),
                  onPressed: actions.copyLink,
                )
              else
                CopyButton(text: link.url, size: 18),
            ],
          ),
        ),
        DetailsPanelItem(
          itemTitle: strings.webPagesFrom,
          leading: ArDriveLink(
            // On the right, like every value in the panel, when it wraps.
            textAlign: TextAlign.right,
            text: webPageSource(context, page),
            onTap: actions.openFolder,
          ),
        ),
        DetailsPanelItem(
          itemTitle: strings.webPagesUpdated,
          leading: DetailsPanelValueText(formatDate(page.updatedAt)),
        ),
      ],
    );
  }
}

import 'dart:math' as math;

import 'package:ardrive/app_shell.dart';
import 'package:ardrive/components/app_top_bar.dart';
import 'package:ardrive/components/details_panel.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/components/side_bar.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/search/search_box.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

// The frame every list page shares - Your drives, Web pages, Names and one
// name's page: the same top bar, title row and details panel, so moving
// between them moves nothing but the content.

/// The page's margin either side of its content.
const double listPagePadding = 16;

/// Between the top bar and the page, and below the table.
const double listPageSectionGap = 24;

/// Between blocks inside the page: the title row and the table.
const double listPageBlockGap = 12;

/// How far above and below its text the title row's tint reaches.
const double listPageTitleInset = 8;

/// The title row's height in all of its forms, so swapping one for another
/// moves nothing below it.
const double listPageTitleMinHeight = 56;

/// Global search, on the list pages as in the explorer.
///
/// The field is the explorer's, and so is the sheet it opens. What differs is
/// how a result is reached: these pages are replaced by the drive a result
/// opens, so the folder is asked for before the selection that carries it
/// ([AppRouterDelegate.requestFolder]).
class ListPageSearchField extends StatelessWidget {
  const ListPageSearchField({super.key});

  @override
  Widget build(BuildContext context) {
    // Read now, not when a result is picked: going to a drive replaces this
    // page, and a context read after that point would be a dead one.
    final router = context.read<AppRouterDelegate>();

    return SearchBox(
      onNavigateToFolder: (driveId, folderId, {itemId}) =>
          router.requestFolder(driveId, folderId, itemId: itemId),
    );
  }
}

/// A list page's chrome: on desktop the top bar (search, sync, profile) over
/// the page; on a phone the drawer and the app bar with search.
///
/// It follows the app shell's own desktop/mobile split, because it has to
/// agree with it: the shell wraps the page in a Scaffold on desktop and in
/// nothing at all on mobile.
class ListPageChrome extends StatelessWidget {
  const ListPageChrome({super.key, required this.child, this.desktopChild});

  final Widget child;

  /// What desktop shows under the top bar instead of [child]: the list with
  /// its details beside it, which a phone has no room for.
  final Widget? desktopChild;

  @override
  Widget build(BuildContext context) {
    return ScreenTypeLayout.builder(
      mobile: (context) => Scaffold(
        drawerScrimColor: ArDriveTheme.of(context)
            .themeData
            .colorTokens
            .containerRaised
            .withOpacity(0.5),
        drawer: const AppSideBar(),
        appBar: MobileAppBar(
          showSearch: true,
          onSearchNavigateToFolder: (driveId, folderId, {itemId}) =>
              context.read<AppRouterDelegate>().requestFolder(
                    driveId,
                    folderId,
                    itemId: itemId,
                  ),
        ),
        body: child,
      ),
      desktop: (context) => Padding(
        padding: const EdgeInsets.only(top: 32, right: listPagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ListPageTopBar(),
            const SizedBox(height: listPageSectionGap),
            Expanded(child: desktopChild ?? child),
          ],
        ),
      ),
    );
  }
}

/// Search on the left, capped; sync and the profile on the right.
class ListPageTopBar extends StatelessWidget {
  const ListPageTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: const ListPageSearchField(),
            ),
          ),
        ),
        const SizedBox(width: 24),
        const SyncButton(),
        const SizedBox(width: 16),
        const ProfileCard(),
      ],
    );
  }
}

/// The page's title on the left and its main action on the right.
///
/// [highlighted] tints the row the colour of a ticked row, for a title row
/// that has become the selection, as Your drives' does.
class ListPageTitleRow extends StatelessWidget {
  const ListPageTitleRow({
    super.key,
    required this.title,
    this.action,
    this.highlighted = false,
  });

  /// The title, or whatever stands in for it.
  final Widget title;
  final Widget? action;
  final bool highlighted;

  /// The title as every list page writes it.
  static Widget text(BuildContext context, String title, {Key? key}) => Text(
        title,
        key: key,
        style: ArDriveTypographyNew.of(context).heading3(
          color: ArDriveTheme.of(context).themeData.colorTokens.textHigh,
          fontWeight: ArFontWeight.bold,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tint =
        ArDriveTheme.of(context).themeData.tableTheme.selectedItemColor;
    final action = this.action;

    return Padding(
      padding: const EdgeInsets.only(
        top: listPagePadding - listPageTitleInset,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(
          horizontal: listPagePadding,
          vertical: listPageTitleInset,
        ),
        constraints: const BoxConstraints(minHeight: listPageTitleMinHeight),
        decoration: BoxDecoration(
          color: highlighted ? tint : tint.withOpacity(0),
          borderRadius: BorderRadius.circular(8),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: title),
              if (action != null) ...[
                const SizedBox(width: 16),
                // Its own width, capped at half the row, so on a narrow
                // screen its label is cut short rather than pushed off the
                // edge.
                ConstrainedBox(
                  constraints:
                      BoxConstraints(maxWidth: constraints.maxWidth / 2),
                  child: action,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Where a list page's body says something instead of listing: loading, an
/// error, nothing yet. The table's card behind it, as the drives list draws
/// its own states.
class ListPageMessage extends StatelessWidget {
  const ListPageMessage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        listPagePadding,
        listPageBlockGap,
        listPagePadding,
        listPageSectionGap,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: listPageSectionGap,
          vertical: 48,
        ),
        decoration: BoxDecoration(
          color: ArDriveTheme.of(context).themeData.tableTheme.backgroundColor,
          borderRadius: BorderRadius.circular(cardDefaultBorderRadius),
        ),
        child: Center(child: child),
      ),
    );
  }
}

/// A row's details beside the list, the explorer's own panel layout.
///
/// Which row is chosen lives here rather than in a cubit: it is a fact
/// about this page's layout, gone when the page is.
///
/// The panel pushes the list narrower, as the explorer's does, while the list
/// keeps its rows as rows ([pushesList]). Where it cannot, the panel covers
/// the right of the list instead: pushing would turn the rows into taller
/// cards, and every row would move under the pointer between the two clicks
/// of a double-click.
///
/// The list sits at the same place in the tree whichever it is, so opening
/// the panel never rebuilds a row: a rebuilt row would forget the first click
/// of a double-click, and its focus.
class ListDetailsHost extends StatefulWidget {
  const ListDetailsHost({
    super.key,
    required this.buildBody,
    required this.panelFor,
    this.pushesList = listDetailsPushList,
    this.initialChosenId,
  });

  /// The row whose details are open to begin with: none, except in the
  /// screenshot harness.
  final String? initialChosenId;

  final Widget Function({
    String? chosenId,
    void Function(String id)? onChoose,
  }) buildBody;

  /// The panel for [id], or null when the list no longer shows it - which
  /// closes the panel.
  final Widget? Function(BuildContext context, String id, VoidCallback close)
      panelFor;

  /// Whether a list [width] wide still keeps its columns beside a panel
  /// [panelWidth] wide, at the reader's [textScale].
  final bool Function(double width, double panelWidth, double textScale)
      pushesList;

  /// The explorer's width for its panel: a quarter of the window, never less
  /// than this.
  static const panelMinWidth = 375.0;

  @override
  State<ListDetailsHost> createState() => _ListDetailsHostState();
}

/// The narrowest list that still reads as a table beside a panel: the three
/// columns the list pages other than Your drives draw.
const double listDetailsMinListWidth = 560;

bool listDetailsPushList(double width, double panelWidth, double textScale) =>
    width - panelWidth >= listDetailsMinListWidth * textScale;

class _ListDetailsHostState extends State<ListDetailsHost> {
  late String? _chosenId = widget.initialChosenId;

  void _choose(String id) {
    if (_chosenId != id) {
      setState(() => _chosenId = id);
    }
  }

  void _close() {
    if (_chosenId != null) {
      setState(() => _chosenId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = _chosenId;
    final panel = id == null ? null : widget.panelFor(context, id, _close);

    // A row the list no longer shows leaves nothing behind to reappear when
    // it comes back.
    if (id != null && panel == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _chosenId == id) _close();
      });
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final panelWidth = math.max(
            ListDetailsHost.panelMinWidth,
            MediaQuery.sizeOf(context).width * 0.25,
          );
          final fontSize =
              ArDriveTypographyNew.of(context).paragraphSmall().fontSize ?? 14;
          final textScale = fontSize <= 0
              ? 1.0
              : MediaQuery.textScalerOf(context).scale(fontSize) / fontSize;

          final pushes = panel != null &&
              widget.pushesList(constraints.maxWidth, panelWidth, textScale);
          final covers = panel != null && !pushes;

          return Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: widget.buildBody(
                      chosenId: panel == null ? null : id,
                      onChoose: _choose,
                    ),
                  ),
                  // The explorer's animation, the explorer's width.
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: pushes
                        ? SizedBox(width: panelWidth, child: panel)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
              if (covers)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: panelWidth,
                  // Over the list, so it needs its own ground and an edge.
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: ArDriveTheme.of(context).themeData.backgroundColor,
                      boxShadow: [
                        BoxShadow(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colorTokens
                              .shadow,
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: panel,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// A list page's details panel, in the explorer panel's frame: the toolbar
/// with close, the title card, then one card of details.
///
/// The explorer's [DetailsPanel] is built around a drive item and its tabs;
/// this shares its toolbar ([DetailsPanelToolbarFrame]) and title card
/// ([DetailsPanelTitleCard]) and puts plain rows of details under them.
class ListDetailsPanel extends StatelessWidget {
  const ListDetailsPanel({
    super.key,
    required this.onClose,
    required this.icon,
    required this.title,
    this.marks = const [],
    this.toolbarActions = const [],
    required this.details,
    this.actions = const [],
  });

  final VoidCallback onClose;
  final Widget icon;
  final String title;

  /// Beside the title: a tag.
  final List<Widget> marks;

  /// Icon buttons in the toolbar.
  final List<Widget> toolbarActions;

  /// Rows of details, each a [DetailsPanelItem].
  final List<Widget> details;

  /// Buttons under the details: the row menu's actions.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = ArDriveTheme.of(context).themeData;

    return ArDriveCard(
      backgroundColor: theme.tableTheme.backgroundColor,
      contentPadding: const EdgeInsets.all(24),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetailsPanelToolbarFrame(
            actions: toolbarActions,
            onClose: onClose,
          ),
          const SizedBox(height: 24),
          DetailsPanelTitleCard(leading: icon, title: title, trailing: marks),
          const SizedBox(height: 24),
          Expanded(
            child: ArDriveCard(
              backgroundColor: theme.colorTokens.containerRaised,
              contentPadding: const EdgeInsets.all(24),
              content: ListView(
                children: [
                  for (final item in details) ...[
                    item,
                    const SizedBox(height: 18),
                  ],
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 8, children: actions),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

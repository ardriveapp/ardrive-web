import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// The table every list page draws - Your drives, Web pages, Names and one
// name's records - so the four read as one app: the same header, the same
// row height, hover, click model and menu gutter. Your drives' rows were the
// model; their reasons are kept with the pieces they explain.

/// The padding a row puts either side of its content.
///
/// Public because the layout decision is made outside the row and has to be
/// made on the width the row will actually lay out in.
const double listRowHorizontalPadding = 16;

/// The width of the selection column, header and rows alike.
///
/// One constant for both so the ticks line up down the table - the usual
/// failure is a header drawn inside the table's own padding and rows drawn
/// outside it, which offsets the two by exactly that padding.
const double listCheckboxColumn = 40;

/// Ticking rows, for a list that can act on several of them at once.
///
/// Only a list with bulk actions passes one - Your drives, whose ticks choose
/// what Sync selected acts on. A list without (Web pages, Names) passes none
/// and gets no checkboxes at all: no box on hover, no select-all, no long
/// press. A future list gets them once it has something to do with them.
///
/// The boxes follow [ArDriveMultiSelect]: a row's box shows while the pointer
/// is on the row or the row has focus, and every box shows while [selecting].
class ListRowSelection {
  const ListRowSelection({
    required this.ticked,
    required this.onTickChanged,
    required this.selecting,
    this.onLongPress,
    this.checkboxKey,
  });

  /// Whether this row is ticked.
  final bool ticked;
  final VoidCallback onTickChanged;

  /// Whether the reader is choosing several rows, which shows every box -
  /// see [ArDriveMultiSelect.isSelecting].
  final bool selecting;

  /// A long press on the row, on a touch screen: starts selecting.
  final VoidCallback? onLongPress;
  final Key? checkboxKey;
}

/// The header's select-all, for a list with bulk actions - see
/// [ListRowSelection].
class ListHeaderSelection {
  const ListHeaderSelection({
    required this.allTicked,
    required this.onToggleAll,
    required this.selecting,
  });

  /// Whether every row is ticked.
  final bool allTicked;
  final VoidCallback onToggleAll;

  /// Whether the reader is choosing several rows: select-all shows only then.
  final bool selecting;
}

/// How big a row's actions menu tap target is.
///
/// The touch minimum, and no larger: a row that draws columns is 48px tall -
/// its content inside [listRowVerticalPadding] either side - so a target of
/// exactly this size is the largest one that cannot make a row taller than it
/// already is.
const double listMenuTapTarget = 48;

/// The trailing gutter every row and the header reserve for that menu.
///
/// Reserved whether or not a menu is drawn, so the header's columns and a
/// row's columns are laid out in the same width in every state.
const double listMenuGutter = listMenuTapTarget + 8;

const double listRowVerticalPadding = ArDriveSpacing.sm;
const double listColumnGap = ArDriveSpacing.md;
const double listStackedGap = ArDriveSpacing.xxs;

/// The least a row's content may be, so a row is the menu's target tall
/// whether or not it draws a menu.
const double listRowContentMinHeight =
    listMenuTapTarget - 2 * listRowVerticalPadding;

/// The card behind a table's header and rows: its top and bottom padding.
const double listPanelPadding = 8;

/// One column of a table: its heading, its share of the width, and the key
/// it sorts by, if it sorts.
class ListColumn<T> {
  const ListColumn(this.label, this.flex, {this.sortKey});

  final String label;
  final int flex;
  final T? sortKey;
}

/// Cells laid out at their columns' shares, with the table's gap between.
///
/// The header and the rows both lay out through this, so a heading cannot
/// drift out of line with the column under it.
class ListColumnsRow extends StatelessWidget {
  const ListColumnsRow({
    super.key,
    required this.flexes,
    required this.cells,
  }) : assert(flexes.length == cells.length);

  final List<int> flexes;
  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: listColumnGap),
          Expanded(flex: flexes[i], child: cells[i]),
        ],
      ],
    );
  }
}

/// The column headings, drawn only where there are columns to head.
class ListTableHeader<T> extends StatelessWidget {
  const ListTableHeader({
    super.key,
    required this.columns,
    this.sort,
    this.sortAscending = true,
    this.onSort,
    this.selection,
  });

  final List<ListColumn<T>> columns;

  /// Which column is ordering the list, if this header is sortable.
  final T? sort;

  /// Which way that column is ordered.
  final bool sortAscending;

  /// Called with the column whose heading was pressed. A header with no
  /// handler draws as plain text and takes no taps.
  final void Function(T column)? onSort;

  /// Select-all, for a list with bulk actions; null for one without, which
  /// draws no checkbox column at all - see [ListRowSelection].
  final ListHeaderSelection? selection;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: listRowHorizontalPadding,
        vertical: listStackedGap,
      ),
      child: Row(
        children: [
          if (selection case final selection?)
            ArDriveMultiSelectBox(
              visible: selection.selecting,
              width: listCheckboxColumn,
              child: ArDriveCheckBox(
                key: const ValueKey('select-all'),
                // A Tab stop only while there is a selection to act on.
                inTabOrder: selection.selecting,
                checked: selection.allTicked,
                onChange: (_) => selection.onToggleAll(),
              ),
            ),
          Expanded(
            child: ListColumnsRow(
              flexes: [for (final c in columns) c.flex],
              cells: [for (final c in columns) _heading(context, c)],
            ),
          ),
          // The rows' menu gutter, so the headings sit over their own columns.
          const SizedBox(width: listMenuGutter),
        ],
      ),
    );
  }

  Widget _heading(BuildContext context, ListColumn<T> column) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final key = column.sortKey;
    final isSorted = key != null && key == sort;

    final label = Text(
      column.label,
      overflow: TextOverflow.ellipsis,
      // The explorer's column headings exactly: paragraphNormal in textMid,
      // semi-bold, so every table reads as the same component.
      style: typography.paragraphNormal(
        // The ordering column names itself by weight and colour as well as by
        // the arrow, so which one is sorting survives a glance.
        color: isSorted ? colorTokens.textHigh : colorTokens.textMid,
        fontWeight: ArFontWeight.semiBold,
      ),
    );

    // The arrow occupies its slot whether or not it is drawn, so pressing a
    // heading does not shuffle the others sideways.
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: label),
        SizedBox(
          width: 18,
          child: isSorted
              ? Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 14,
                    color: colorTokens.textHigh,
                  ),
                )
              : null,
        ),
      ],
    );

    if (key == null || onSort == null) {
      return content;
    }

    return ArDriveClickArea(
      child: Semantics(
        button: true,
        label: column.label,
        child: InkWell(
          onTap: () => onSort!(key),
          child: content,
        ),
      ),
    );
  }
}

/// A row's first cell: an icon, the name, an optional quieter second line,
/// and marks beside the name.
class ListNameCell extends StatelessWidget {
  const ListNameCell({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.marks = const [],
  });

  final Widget icon;
  final String title;
  final String? subtitle;

  /// Beside the name, wrapping under it when they do not fit: tags, a dot.
  final List<Widget> marks;

  static const iconSize = 20.0;
  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    // The name and its marks together, allowed to become two lines: a rigid
    // mark beside the name is what squeezed the name to nothing on a phone.
    final name = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: _gap,
      runSpacing: 2,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: typography.paragraphNormal(
            color: colorTokens.textHigh,
            fontWeight: ArFontWeight.semiBold,
          ),
        ),
        ...marks,
      ],
    );
    final subtitle = this.subtitle;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: _gap),
        Flexible(
          child: subtitle == null
              ? name
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    name,
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typography.paragraphSmall(
                        color: colorTokens.textLow,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// A plain cell: one line of quieter text.
class ListTextCell extends StatelessWidget {
  const ListTextCell(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: ArDriveTypographyNew.of(context)
          .paragraphSmall(color: color ?? colorTokens.textMid)
          .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}

/// One row of a list page's table, or a stacked card on a narrow screen.
///
/// A single click chooses the row - its details open beside the list where
/// there are any - and never ticks it; a double-click, a tap on a touch
/// screen, Enter or a screen reader's activate opens it. The explorer's rule,
/// from [ArDriveDoubleClick].
class ListTableRow extends StatelessWidget {
  const ListTableRow({
    super.key,
    required this.semanticLabel,
    required this.onOpen,
    required this.showsColumns,
    required this.child,
    this.menu,
    this.selection,
    this.chosen,
    this.onChoose,
    this.selectable = true,
  });

  /// False for a row that can't be ticked while the others can: its box's
  /// column stays, empty, so its columns line up with theirs, and it takes no
  /// long press or Space.
  final bool selectable;

  /// What a screen reader calls the row's button.
  final String semanticLabel;

  /// A double-click, a tap on a touch screen, or Enter.
  final VoidCallback? onOpen;

  /// The table's columns, or the stacked card. Told, never worked out here:
  /// the header above is drawn from the same answer.
  final bool showsColumns;

  /// The row's content: its columns, or the stacked card.
  final Widget child;

  /// The row's own actions, drawn in the gutter it always reserves.
  final Widget? menu;

  /// Ticking, for a list with bulk actions; null for one without, which
  /// draws no checkbox and takes no long press - see [ListRowSelection].
  final ListRowSelection? selection;

  /// Whether this row's details are open beside the list, or null where no
  /// details can be open. Then the row is drawn chosen while it has focus,
  /// the one other sign that a click landed.
  final bool? chosen;

  /// A click on the row, or focus reaching it: show its details.
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    // Columns only: a stacked card on a phone has no checkbox.
    final selection = showsColumns ? this.selection : null;
    final hasCheckbox = selection != null;

    return ListRowHighlight(
      // The table's hover, as the explorer's rows have it. containerL1 is
      // darker than the table in the dark theme, so a hovered row there all
      // but vanished.
      colour: ArDriveTheme.of(context).themeData.tableTheme.hoverItemColor,
      // The explorer's own colour for a chosen row.
      selectedColour:
          ArDriveTheme.of(context).themeData.tableTheme.selectedItemColor,
      selected: selectable && (selection?.ticked ?? false),
      chosen: chosen,
      onFocusGained: onChoose,
      child: Container(
        // No hairlines between table rows: the explorer separates its rows
        // with the card ground and hover alone. A stacked card keeps its rule,
        // or two run together.
        decoration: showsColumns
            ? null
            : BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colorTokens.strokeLow),
                ),
              ),
        // The menu sits beside the row's content rather than inside it, so
        // the tap that opens the row and the tap that opens the menu are two
        // targets rather than one on top of the other.
        child: Row(
          children: [
            Expanded(
              child: ArDriveClickArea(
                child: Semantics(
                  button: true,
                  label: semanticLabel,
                  child: ListSelectOrOpen(
                    onOpen: onOpen,
                    onChoose: onChoose,
                    onLongPress: selectable ? selection?.onLongPress : null,
                    onSpace: selectable ? selection?.onTickChanged : null,
                    child: _yieldLongPress(
                      selectable && selection?.onLongPress != null,
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: listRowHorizontalPadding,
                          vertical: listRowVerticalPadding,
                        ),
                        // The box inside the row's tap target: shown, it
                        // takes its own tap and ticks; hidden, a tap passes
                        // through to the row, so its spot is not dead.
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: listRowContentMinHeight,
                          ),
                          child: hasCheckbox
                              ? Row(
                                  children: [
                                    if (selectable)
                                      _RowCheckbox(
                                        selection: selection,
                                        semanticLabel: semanticLabel,
                                      )
                                    else
                                      const SizedBox(width: listCheckboxColumn),
                                    Expanded(child: child),
                                  ],
                                )
                              : child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: listMenuGutter,
              // `heightFactor: 1` so the gutter is as tall as the menu and no
              // taller: a plain Center fills a bounded height and set the
              // row's height instead of fitting inside it.
              child: menu == null
                  ? null
                  : Align(
                      alignment: Alignment.center,
                      heightFactor: 1,
                      child: menu,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [child], with any tooltip in it leaving a long press to the row when the
/// row starts selecting on one - see [ArDriveTooltipLongPressYields].
Widget _yieldLongPress(bool rowTakesLongPress, Widget child) =>
    rowTakesLongPress ? ArDriveTooltipLongPressYields(child: child) : child;

/// A row's checkbox, in its reserved column: shown while the reader is
/// selecting, or while this row is under the pointer or has focus.
class _RowCheckbox extends StatelessWidget {
  const _RowCheckbox({required this.selection, required this.semanticLabel});

  final ListRowSelection selection;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final attention = _RowAttention.of(context);

    return ArDriveMultiSelectBox(
      visible: ArDriveMultiSelect.showsRowCheckbox(
        selecting: selection.selecting,
        hovered: attention.hovered,
        focused: attention.focused,
      ),
      width: listCheckboxColumn,
      // Its own target, so ticking is never mistaken for opening.
      child: ArDriveCheckBox(
        key: selection.checkboxKey,
        semanticLabel: semanticLabel,
        // The row is the Tab stop and Space on it ticks this, as in a file
        // manager: a box per row would double the stops on the page. Still
        // tappable, and still a checkbox to a screen reader.
        inTabOrder: false,
        checked: selection.ticked,
        onChange: (_) => selection.onTickChanged(),
      ),
    );
  }
}

/// Whether a row is under the pointer and whether focus is in it, from
/// [ListRowHighlight], for its checkbox.
class _RowAttention extends InheritedWidget {
  const _RowAttention({
    required this.hovered,
    required this.focused,
    required super.child,
  });

  final bool hovered;
  final bool focused;

  static _RowAttention of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RowAttention>() ??
      const _RowAttention(hovered: false, focused: false, child: SizedBox());

  @override
  bool updateShouldNotify(_RowAttention oldWidget) =>
      hovered != oldWidget.hovered || focused != oldWidget.focused;
}

/// A row's tap, read the way a file manager reads it - see [ListTableRow].
///
/// The highlight is keyboard focus. A click puts focus on the row, which is
/// what lets Enter open it straight after, and Tab moves the same highlight
/// from row to row.
class ListSelectOrOpen extends StatefulWidget {
  const ListSelectOrOpen({
    super.key,
    required this.onOpen,
    required this.child,
    this.onChoose,
    this.onLongPress,
    this.onSpace,
  });

  final VoidCallback? onOpen;

  /// A long press: see [ListRowSelection.onLongPress].
  final VoidCallback? onLongPress;

  /// Space on the focused row: ticks its box, where the list has one. Enter
  /// still opens.
  final VoidCallback? onSpace;

  /// Called on the click itself as well as when focus arrives: a row that
  /// already has focus - the one whose details were just closed - reports no
  /// change of focus when clicked again.
  final VoidCallback? onChoose;
  final Widget child;

  @override
  State<ListSelectOrOpen> createState() => _ListSelectOrOpenState();
}

class _ListSelectOrOpenState extends State<ListSelectOrOpen> {
  final _doubleClick = ArDriveDoubleClick<Object>();
  final _focusNode = FocusNode(debugLabel: 'ListTableRow');
  static const _thisRow = Object();
  PointerDeviceKind? _kind;

  @override
  void dispose() {
    _doubleClick.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTap() {
    final kind = _kind;
    _kind = null;

    if (_doubleClick.completes(_thisRow) || ArDriveDoubleClick.tapOpens(kind)) {
      widget.onOpen?.call();
      return;
    }

    _focusNode.requestFocus();
    widget.onChoose?.call();
    _doubleClick.arm(_thisRow);
  }

  @override
  Widget build(BuildContext context) {
    final onSpace = widget.onSpace;

    // Above the row's own focus, where a key from it is heard first: without
    // this, Space would activate the row and open it.
    return CallbackShortcuts(
      bindings: {
        if (onSpace != null)
          const SingleActivator(LogicalKeyboardKey.space): onSpace,
      },
      child: _inkWell(),
    );
  }

  Widget _inkWell() {
    return InkWell(
      focusNode: _focusNode,
      // The row paints its own highlight across its full width, checkbox and
      // menu included; the InkWell's would cover only the middle.
      focusColor: Colors.transparent,
      onTapDown: (details) => _kind = details.kind,
      onTapCancel: () => _kind = null,
      onTap: _onTap,
      onLongPress: widget.onLongPress,
      child: widget.child,
    );
  }
}

/// Paints a row's hover state, and its selected state.
///
/// An InkWell's hover needs a `Material` ancestor that a table built out of
/// Containers does not provide, so this owns the state instead.
class ListRowHighlight extends StatefulWidget {
  const ListRowHighlight({
    super.key,
    required this.colour,
    required this.selectedColour,
    required this.selected,
    required this.child,
    this.chosen,
    this.onFocusGained,
  });

  final Color colour;
  final Color selectedColour;
  final bool selected;
  final Widget child;

  /// See [ListTableRow.chosen].
  final bool? chosen;

  /// Called when focus arrives anywhere in the row: a click, or Tab.
  final VoidCallback? onFocusGained;

  @override
  State<ListRowHighlight> createState() => _ListRowHighlightState();
}

class _ListRowHighlightState extends State<ListRowHighlight> {
  bool _isHovering = false;

  /// Whether focus is anywhere in the row: the row just clicked, or reached
  /// with Tab.
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: ColoredBox(
        // Where details can be open, the highlight is theirs: it goes when
        // they are closed. Elsewhere, focus is the only sign a click landed.
        color: widget.selected || (widget.chosen ?? _hasFocus)
            ? widget.selectedColour
            : _isHovering
                ? widget.colour
                : Colors.transparent,
        // Not focusable itself; it only hears when something inside the row
        // takes focus or gives it up.
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          includeSemantics: false,
          onFocusChange: (hasFocus) {
            setState(() => _hasFocus = hasFocus);
            if (hasFocus) {
              widget.onFocusGained?.call();
            }
          },
          child: _RowAttention(
            hovered: _isHovering,
            focused: _hasFocus,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// The card a table's header and rows sit in, as a sliver, so the rows stay
/// lazily built and the page scrolls as one.
///
/// Columns only: a stacked list on a phone has its own rules and no card,
/// like the explorer's phone view.
class ListTablePanel extends StatelessWidget {
  const ListTablePanel({
    super.key,
    required this.header,
    required this.rows,
  });

  final Widget header;

  /// A sliver of rows.
  final Widget rows;

  @override
  Widget build(BuildContext context) {
    final theme = ArDriveTheme.of(context).themeData;
    return DecoratedSliver(
      decoration: BoxDecoration(
        color: theme.tableTheme.backgroundColor,
        borderRadius: BorderRadius.circular(cardDefaultBorderRadius),
      ),
      sliver: SliverMainAxisGroup(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: listPanelPadding)),
          SliverToBoxAdapter(child: header),
          rows,
          const SliverToBoxAdapter(child: SizedBox(height: listPanelPadding)),
        ],
      ),
    );
  }
}

/// A row's ⋮ menu, in the gutter [ListTableRow] reserves: the same target,
/// icon and placement as Your drives' ([listMenuTapTarget]).
class ListRowMenu extends StatelessWidget {
  const ListRowMenu({super.key, required this.items, required this.label});

  final List<ArDriveDropdownItem> items;

  /// The button's name, said once: "Show menu".
  final String label;

  static const iconSize = 20.0;

  @override
  Widget build(BuildContext context) {
    return ArDriveDropdown(
      // Opens upward for a row near the bottom of the screen, rather than off
      // its end.
      calculateVerticalAlignment: (isBelowHalfScreen) =>
          isBelowHalfScreen ? Alignment.bottomRight : Alignment.topRight,
      anchor: const Aligned(
        follower: Alignment.topRight,
        target: Alignment.bottomRight,
        shiftToWithinBound: AxisFlag(x: true),
      ),
      items: items,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: ArDriveClickArea(
          tooltip: label,
          child: SizedBox(
            width: listMenuTapTarget,
            height: listMenuTapTarget,
            child: Center(child: ArDriveIcons.kebabMenu(size: iconSize)),
          ),
        ),
      ),
    );
  }
}

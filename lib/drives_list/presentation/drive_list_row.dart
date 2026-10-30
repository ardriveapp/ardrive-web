import 'package:ardrive/components/drive_fingerprint.dart';
import 'package:ardrive/components/list_page/list_table.dart';
import 'package:ardrive/drives_list/domain/drive_list_item.dart';
import 'package:ardrive/publication/presentation/publish_to_web.dart';
import 'package:ardrive/drives_list/domain/drive_list_sort.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/format_date.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The narrowest a row may be and still be drawn as five columns, at a text
/// scale of 1.
///
/// Measured on the width a row actually has for its content - the page's
/// width less the padding either side - because that is what the columns have
/// to fit into. Chosen so the widest thing the "last synced" column ever says
/// still fits: see [driveListSyncColumnMinimum].
///
/// A measurement of text, so it is only ever used multiplied by the reader's
/// text scale - see [driveListShowsColumns].
const double driveListColumnsFrom = 760;

/// The width the "last synced" column is required to have wherever there are
/// columns at all.
///
/// "Synced 59 minutes ago" is the longest sentence that column produces, and
/// it is the one fact this whole page exists to report - a breakpoint that
/// draws five columns and then clips that sentence has chosen the layout over
/// the content. That sentence measures 133px in Wavehaus at this size, taken
/// off the font's own metrics; the margin above it is rounding. This is what
/// fixes [driveListColumnsFrom] and [_syncFlex] rather than either being
/// picked by eye.
///
/// At a text scale of 1, like everything it is derived from. A larger scale is
/// handled where the decision is made, by scaling the breakpoint - see
/// [driveListShowsColumns] - rather than by leaving slack in a measurement.
const double driveListSyncColumnMinimum = 150;

/// The padding a row puts either side of its content: the shared table's
/// ([listRowHorizontalPadding]).
const double driveListRowHorizontalPadding = listRowHorizontalPadding;

/// The width of the selection column - see [listCheckboxColumn].
const double driveListCheckboxColumn = listCheckboxColumn;

/// How big the per-row actions menu's tap target is - see
/// [listMenuTapTarget]. `drives_list_menu_test.dart` measures it against the
/// row's height.
const double driveListMenuTapTarget = listMenuTapTarget;

/// The trailing gutter every row and the header reserve for that menu - see
/// [listMenuGutter].
const double driveListMenuGutter = listMenuGutter;

/// Whether a list this wide draws columns.
///
/// One decision for the whole list, made once by the page and handed to every
/// row and to the header. Rows deciding for themselves is what put a table
/// header over stacked cards: each was answering about a different width.
///
/// The menu's gutter comes off the width first, for the same reason the
/// padding does: it is width the columns do not get, and a breakpoint that
/// ignores it hands [driveListColumnsFrom] 56px less than it was measured
/// for - which is how "Synced 59 minutes ago" starts clipping again.
///
/// [textScale] is the other half of the same argument. All five columns are
/// text and every one of them is a single ellipsized line, so at a large text
/// scale the same pixel width holds proportionally less of each - and the
/// layout that fitted at 1.0 goes on being chosen while it silently truncates
/// the values inside it. A count cut mid-digit still reads as a count: "128456
/// items" clipped to "12845..." is not a smaller number, it is a wrong one.
/// Above roughly 1.55x this can no longer be satisfied at any width the page
/// allows, and every row is the stacked card, which wraps instead of clipping.
bool driveListShowsColumns(double contentWidth, {double textScale = 1}) =>
    contentWidth - driveListRowHorizontalPadding * 2 - driveListMenuGutter >=
    driveListColumnsFrom * textScale;

/// Stands in for a number we are deliberately not reporting.
///
/// Not a zero: a drive nothing has looked at holds no local rows, and "0
/// items, 0 B" is a confident answer to a question we have not asked. The
/// tooltip says which it is.
///
/// ASCII deliberately. An em dash is the typographically right mark and
/// Wavehaus does not contain one - nor an en dash, nor an ellipsis - so it
/// renders out of the brand face in whatever the fallback happens to be.
const String driveListWithheldFigure = '-';

const double _columnGap = listColumnGap;
const double _stackedGap = listStackedGap;
const double _iconSize = ListNameCell.iconSize;

/// The narrowest a row may be and still be drawn as three columns - name,
/// last synced and size - at a text scale of 1.
///
/// Used wherever the five columns do not fit, so a list in a mid-width window
/// keeps its checkboxes, headings and sorting rather than turning into
/// cards. The two columns it drops, files and created, are what a drive's
/// details show. Derived the same way as [driveListColumnsFrom]: the
/// last synced column keeps its [driveListSyncColumnMinimum], now as four of
/// twelve shares rather than four of seventeen.
const double driveListCompactColumnsFrom = 540;

/// Whether a list this wide draws the three columns - see
/// [driveListCompactColumnsFrom] and [driveListShowsColumns], whose rules this
/// follows.
bool driveListShowsCompactColumns(
  double contentWidth, {
  double textScale = 1,
}) =>
    contentWidth - driveListRowHorizontalPadding * 2 - driveListMenuGutter >=
    driveListCompactColumnsFrom * textScale;

/// Whether a drive's details, [panelWidth] wide, push a list that has
/// [width] to itself, or cover its right side instead.
///
/// They push, as the explorer's do, while the list keeps at least the three
/// columns beside the panel. Otherwise they cover. Pushing a list of cards,
/// or pushing a list of rows into cards, changes how tall every row is, and
/// every row would move under the pointer between the two clicks of a
/// double-click. A list that has three columns beside the panel had at least
/// three without it, so only the narrower width is measured.
///
/// The list fills the width it is given, so that is the width it measures.
bool driveDetailsPushList({
  required double width,
  required double panelWidth,
  double textScale = 1,
}) {
  final listWidth = width - panelWidth;

  return driveListShowsColumns(listWidth, textScale: textScale) ||
      driveListShowsCompactColumns(listWidth, textScale: textScale);
}

/// The share of a wide row each column gets.
const int _nameFlex = 6;
const int _syncFlex = 4;
const int _filesFlex = 2;
const int _sizeFlex = 2;
// One unit lighter than the name: a created date is a constant ~90px,
// while a drive name is unbounded and is the field that identifies the
// row - so the slack belongs to the name.
const int _createdFlex = 3;

/// The column headings, drawn only where there are columns to head: the
/// shared [ListTableHeader] with the drives list's columns.
///
/// It shares the row's flex constants rather than repeating them: a heading
/// that drifts out of line with the column under it is worse than no heading.
class DriveListHeader extends StatelessWidget {
  const DriveListHeader({
    super.key,
    this.sort,
    this.sortAscending = true,
    this.onSort,
    this.allSelected,
    this.onToggleSelectAll,
    this.selecting = false,
    this.showsAllColumns = true,
  });

  /// Whether the reader is choosing several drives: select-all shows only
  /// then - see [ListHeaderSelection].
  final bool selecting;

  /// False for the three columns drawn wherever five do not fit - see
  /// [driveListCompactColumnsFrom].
  final bool showsAllColumns;

  /// Which column is ordering the list, if this header is sortable.
  final DriveListSort? sort;

  /// Which way that column is ordered.
  final bool sortAscending;

  /// Called with the column whose heading was pressed. A header with no
  /// handler draws as plain text and takes no taps, which is what the tests
  /// that only care about layout get.
  final void Function(DriveListSort column)? onSort;

  /// Whether every drive on screen is ticked, some are, or none - null when
  /// the list is not offering selection.
  final bool? allSelected;

  final VoidCallback? onToggleSelectAll;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);

    return ListTableHeader<DriveListSort>(
      sort: sort,
      sortAscending: sortAscending,
      onSort: onSort,
      selection: allSelected == null
          ? null
          : ListHeaderSelection(
              allTicked: allSelected!,
              onToggleAll: () => onToggleSelectAll?.call(),
              selecting: selecting,
            ),
      columns: [
        ListColumn(strings.name, _nameFlex, sortKey: DriveListSort.name),
        ListColumn(strings.lastSynced, _syncFlex,
            sortKey: DriveListSort.lastSynced),
        if (showsAllColumns)
          ListColumn(strings.driveListFilesHeading, _filesFlex,
              sortKey: DriveListSort.files),
        ListColumn(strings.size, _sizeFlex, sortKey: DriveListSort.size),
        if (showsAllColumns)
          ListColumn(strings.dateCreated, _createdFlex,
              sortKey: DriveListSort.created),
      ],
    );
  }
}

/// One drive, as a row on a wide screen and a stacked card on a narrow one.
class DriveListRow extends StatelessWidget {
  const DriveListRow({
    super.key,
    required this.drive,
    required this.onOpen,
    required this.showsColumns,
    this.showsAllColumns = true,
    this.menu,
    this.selected,
    this.onSelectedChanged,
    this.selecting = false,
    this.onLongPress,
    this.chosen,
    this.onChoose,
  });

  /// Whether the reader is choosing several drives, which shows every row's
  /// box - see [ListRowSelection.selecting]. Otherwise a row's box shows
  /// while the pointer is on it or it has focus.
  final bool selecting;

  /// See [ListRowSelection.onLongPress].
  final VoidCallback? onLongPress;

  /// False for the three columns drawn wherever five do not fit - see
  /// [driveListCompactColumnsFrom].
  final bool showsAllColumns;

  /// Whether this drive's details are open beside the list, or null where no
  /// details can be open. Then the row is drawn chosen while it has focus,
  /// the one other sign that a click landed.
  final bool? chosen;

  /// A click on the row, or focus reaching it: show this drive's details.
  /// The same act as choosing a row in the explorer, which opens its details
  /// beside the table.
  final VoidCallback? onChoose;

  final DriveListItem drive;

  /// Opening the drive: a double-click, a tap on a touch screen, or Enter.
  ///
  /// A single click only highlights the row, the way a click on a row in the
  /// explorer does. It does not tick the row's checkbox: ticking is the
  /// selection that Sync acts on, and a click that quietly narrowed Sync to
  /// one drive would be a trap. It would also put the selection strip above
  /// the list, shifting every row down between the two clicks of a
  /// double-click so the second landed on a different drive.
  final VoidCallback onOpen;

  /// The drive's own actions, drawn in the gutter this row already reserves.
  ///
  /// Handed in rather than built here so a row can still be rendered - and
  /// measured - with nothing but a [DriveListItem]: the menu needs the drive
  /// record and three app-wide blocs, and none of that is what a row is about.
  final Widget? menu;

  /// Whether to draw the five columns or the stacked card.
  ///
  /// Told, never worked out here - see [driveListShowsColumns]. The heading
  /// above these rows is drawn from the same answer, and the two disagreeing
  /// is a table header over a column of cards.
  final bool showsColumns;

  /// Whether this drive is ticked, or null when the list is not offering
  /// selection at all - which is how the checkbox disappears entirely rather
  /// than being drawn disabled.
  final bool? selected;

  final void Function(String driveId)? onSelectedChanged;

  @override
  Widget build(BuildContext context) {
    return ListTableRow(
      semanticLabel: drive.isLocked
          ? '${appLocalizationsOf(context).lockedDriveName}, '
              '${appLocalizationsOf(context).driveLocked}'
          : drive.name,
      onOpen: onOpen,
      showsColumns: showsColumns,
      menu: menu,
      selection: selected == null
          ? null
          : ListRowSelection(
              ticked: selected!,
              onTickChanged: () => onSelectedChanged?.call(drive.id),
              selecting: selecting,
              onLongPress: onLongPress,
              checkboxKey: ValueKey('select-${drive.id}'),
            ),
      chosen: chosen,
      onChoose: onChoose,
      // A locked drive takes no tick: a sync can't read it.
      selectable: !drive.isLocked,
      child: showsColumns ? _columns(context) : _stacked(context),
    );
  }

  Widget _columns(BuildContext context) {
    return ListColumnsRow(
      flexes: [
        _nameFlex,
        _syncFlex,
        if (showsAllColumns) _filesFlex,
        _sizeFlex,
        if (showsAllColumns) _createdFlex,
      ],
      cells: [
        _name(context),
        _syncState(context),
        if (showsAllColumns) _files(context, underHeading: true),
        _size(context),
        if (showsAllColumns) _created(context, underHeading: true),
      ],
    );
  }

  Widget _stacked(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      // Shrink-wrapped. A Column fills the height it is offered by default,
      // which in the sliver this normally lives in is unbounded and therefore
      // harmless - and in any box with a real height is the row growing to
      // fill the screen. The row's height is its content's, wherever it is
      // put.
      mainAxisSize: MainAxisSize.min,
      children: [
        _name(context),
        const SizedBox(height: _stackedGap),
        _syncState(context),
        const SizedBox(height: _stackedGap),
        // Wrapped rather than a Row: at 320px with a large text scale these
        // run past the edge, and this is exactly the overflow this series has
        // already shipped once.
        Wrap(
          spacing: _columnGap,
          runSpacing: _stackedGap / 2,
          children: [
            // A withheld figure is a mark that means nothing without the
            // column heading above it, and there is no heading here. The row
            // already says the drive is not synced on this device, which is
            // the same fact in words.
            if (drive.fileCount != null) _files(context),
            if (drive.totalSize != null) _size(context),
            if (drive.isLocked) _unlockAction(context) else _created(context),
          ],
        ),
      ],
    );
  }

  Widget _name(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    // Its name is encrypted: the row says what it is, and its emoji say which
    // one, the same three desktop shows.
    if (drive.isLocked) {
      return ListNameCell(
        icon: ArDriveTooltip(
          message: appLocalizationsOf(context).driveLocked,
          child: ArDriveIcons.lock(
            size: _iconSize,
            color: colorTokens.textMid,
          ),
        ),
        title: appLocalizationsOf(context).lockedDriveName,
        marks: [DriveFingerprint(driveId: drive.id)],
      );
    }

    return ListNameCell(
      // Public or private, said with the same icon the rest of the app uses
      // for it rather than a word this row has no space for.
      // ArDriveTooltip, not Material's: under a row that starts selecting
      // on a long press, it leaves the long press to the row.
      icon: ArDriveTooltip(
        message: drive.isPrivate
            ? appLocalizationsOf(context).private
            : appLocalizationsOf(context).public,
        child: drive.isPrivate
            ? ArDriveIcons.privateDrive(
                size: _iconSize,
                color: colorTokens.textMid,
              )
            : ArDriveIcons.publicDrive(
                size: _iconSize,
                color: colorTokens.textMid,
              ),
      ),
      title: drive.name,
      marks: [
        if (drive.isSharedWithMe) _SharedMarker(),
        PublishedToWebMark(driveId: drive.id),
      ],
    );
  }

  Widget _syncState(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    // Status, then the one thing to do about it. Unlock is a text action
    // rather than a button: the smallest button is 36 high and made a locked
    // row taller than every other row. A row's height is its text's.
    if (drive.isLocked) {
      final status = Text(
        formatDriveSyncState(context, drive),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: typography.paragraphSmall(color: colorTokens.textLow),
      );

      // Stacked, the action takes the line the created date has on every
      // other card, so the card is as tall as theirs.
      if (!showsColumns) {
        return status;
      }

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: status),
          const SizedBox(width: ArDriveSpacing.sm),
          _unlockAction(context),
        ],
      );
    }

    // A failure is drawn as one. The top bar reports "2 of 12 drives could not
    // be synced" in red with a triangle and sends the reader here to find out
    // which - and this said so in the same grey as "Synced 5 minutes ago", so
    // the one row that needed finding looked like every row that did not.
    // The same 14px triangle the sync history uses, so the two agree.
    if (drive.lastSyncFailed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ArDriveIcons.triangle(size: 14, color: colorTokens.statusErrorFg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              formatDriveSyncState(context, drive),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  typography.paragraphSmall(color: colorTokens.statusErrorFg),
            ),
          ),
        ],
      );
    }

    return Text(
      formatDriveSyncState(context, drive),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: typography.paragraphSmall(
        // A drive nothing has looked at is not an error and is not drawn as
        // one; it is simply the quieter of the two.
        color: drive.hasBeenWalked ? colorTokens.textMid : colorTokens.textLow,
      ),
    );
  }

  /// A locked drive's Unlock, the same act as opening its row.
  Widget _unlockAction(BuildContext context) => ArDriveLink(
        key: ValueKey('unlock-${drive.id}'),
        text: appLocalizationsOf(context).unlock,
        isAction: true,
        style: ArDriveTypographyNew.of(context)
            .paragraphSmall(fontWeight: ArFontWeight.semiBold),
        onTap: onOpen,
      );

  // [underHeading] is true in the table, where the column heading already says
  // what the figure is: "Files" over "15 files" said it twice. The stacked
  // layout has no headings, so there the words stay.
  Widget _files(BuildContext context, {bool underHeading = false}) {
    final fileCount = drive.fileCount;

    return _figure(
      context,
      fileCount == null
          ? driveListWithheldFigure
          : underHeading
              ? NumberFormat.decimalPattern().format(fileCount)
              : appLocalizationsOf(context).driveFileCount(fileCount),
      withheld: fileCount == null,
    );
  }

  Widget _size(BuildContext context) {
    final totalSize = drive.totalSize;

    return _figure(
      context,
      // Withheld until the drive has been walked. `SUM(size)` counts synced
      // rows only, so an unsynced drive reads as 0 B - which is worse than
      // saying nothing, because it looks like an answer.
      totalSize == null ? driveListWithheldFigure : filesize(totalSize),
      withheld: totalSize == null,
    );
  }

  // See [_files] for [underHeading].
  Widget _created(BuildContext context, {bool underHeading = false}) {
    // When a locked drive was made is inside it too.
    if (drive.isLocked) {
      return _figure(context, driveListWithheldFigure, withheld: true);
    }

    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final date = formatDate(drive.dateCreated);

    return Text(
      underHeading
          ? date
          : appLocalizationsOf(context).driveCreatedOnDate(date),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: typography
          .paragraphSmall(color: colorTokens.textLow)
          .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }

  /// A number, or the dash that says we are not going to guess one.
  Widget _figure(
    BuildContext context,
    String text, {
    required bool withheld,
  }) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    final label = Text(
      text,
      // Left, like every other cell in this table and every cell in the
      // explorer's. Right-aligning these two lined their digits up, but it
      // also pushed Size hard against Date Created - a right-aligned column
      // ending where a left-aligned one begins, with only the column gap
      // between them - and made the pair read as shoved to one side.
      textAlign: TextAlign.start,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: typography
          .paragraphSmall(
        color: withheld ? colorTokens.textXLow : colorTokens.textMid,
      )
          .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    );

    // "Not known until synced" is not true of a locked drive: a sync can't
    // read it either.
    if (!withheld || drive.isLocked) {
      return label;
    }

    return ArDriveTooltip(
      message: appLocalizationsOf(context).notKnownUntilSynced,
      child: label,
    );
  }
}

/// Says a drive belongs to somebody else, in place rather than in a section of
/// its own.
class _SharedMarker extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      ArDriveTag(text: appLocalizationsOf(context).driveSharedWithMe);
}

/// What the row says about when this drive was last read.
///
/// Pulled out of the widget so the thresholds can be checked directly. Every
/// branch is a different fact, and none of them is allowed to stand in for
/// another: "not synced" is not "empty", and a bare "Synced" is not a time.
String formatDriveSyncState(
  BuildContext context,
  DriveListItem drive, {
  DateTime? now,
}) {
  if (drive.isLocked) {
    return appLocalizationsOf(context).driveLocked;
  }

  if (drive.isSyncing) {
    return appLocalizationsOf(context).driveSyncingNow;
  }

  // Ahead of the timestamp, because a drive that failed keeps whatever time it
  // last succeeded at - and "Synced 2 days ago" on the one row that just
  // failed is the least useful true thing this row could say.
  if (drive.lastSyncFailed) {
    return appLocalizationsOf(context).driveSyncFailed;
  }

  final lastSyncedAt = drive.lastSyncedAt;

  if (lastSyncedAt == null) {
    // Walked by a build that did not record the time. It has been synced; we
    // just cannot say when, so we do not.
    return drive.hasBeenWalked
        ? appLocalizationsOf(context).driveSyncedTimeUnknown
        : appLocalizationsOf(context).driveNeverSynced;
  }

  final elapsed = (now ?? DateTime.now()).difference(lastSyncedAt);

  if (elapsed.inMinutes < 1) {
    return appLocalizationsOf(context).driveSyncedJustNow;
  }

  if (elapsed.inMinutes < 60) {
    return appLocalizationsOf(context).driveSyncedMinutesAgo(elapsed.inMinutes);
  }

  if (elapsed.inHours < 24) {
    return appLocalizationsOf(context).driveSyncedHoursAgo(elapsed.inHours);
  }

  if (elapsed.inDays < 7) {
    return appLocalizationsOf(context).driveSyncedDaysAgo(elapsed.inDays);
  }

  return appLocalizationsOf(context)
      .driveSyncedOnDate(formatDate(lastSyncedAt));
}

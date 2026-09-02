import 'package:ardrive/drives_list/domain/drive_list_item.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
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

/// How wide the list is allowed to grow.
///
/// Past this, a drive's name and its date are simply far apart: the eye has to
/// travel the whole monitor to read one row, and the columns stop reading as a
/// table. Kept here with the widths it is a width for.
const double driveListMaxContentWidth = 1200;

/// The padding a row puts either side of its content.
///
/// Public because the layout decision is made outside the row and has to be
/// made on the width the row will actually lay out in.
const double driveListRowHorizontalPadding = 16;

/// How big the per-row actions menu's tap target is.
///
/// The touch minimum, and no larger: a row that draws columns is 48px tall -
/// its content inside [_rowVerticalPadding] either side - so a target of
/// exactly this size is the largest one that cannot make a row taller than it
/// already is. `drives_list_menu_test.dart` measures both halves of that.
const double driveListMenuTapTarget = 48;

/// The trailing gutter every row and the header reserve for that menu.
///
/// Reserved whether or not a menu is drawn, so the header's columns and a
/// row's columns are laid out in the same width in every state. A gutter that
/// existed only on the rows would put the headings 56px out of line with the
/// values under them, which is the same class of bug as a table header over a
/// column of cards.
const double driveListMenuGutter = driveListMenuTapTarget + 8;

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

const double _rowVerticalPadding = 14;
const double _columnGap = 16;
const double _stackedGap = 6;
const double _badgeGap = 8;
const double _iconSize = 20;

/// The share of a wide row each column gets.
const int _nameFlex = 6;
const int _syncFlex = 4;
const int _filesFlex = 2;
const int _sizeFlex = 2;
// One unit lighter than the name: a created date is a constant ~90px,
// while a drive name is unbounded and is the field that identifies the
// row - so the slack belongs to the name.
const int _createdFlex = 3;

/// The column headings, drawn only where there are columns to head.
///
/// It shares the row's flex constants rather than repeating them: a heading
/// that drifts out of line with the column under it is worse than no heading.
class DriveListHeader extends StatelessWidget {
  const DriveListHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    Widget heading(String text, int flex, {bool align = false}) => Expanded(
          flex: flex,
          child: Text(
            text,
            textAlign: align ? TextAlign.end : TextAlign.start,
            overflow: TextOverflow.ellipsis,
            // The explorer's column headings exactly: paragraphNormal in
            // textMid, semi-bold. This list had them a step smaller and a
            // shade fainter than its own row text, which is the pairing that
            // made the two tables read as different components rather than
            // the same one twice.
            style: typography.paragraphNormal(
              color: colorTokens.textMid,
              fontWeight: ArFontWeight.semiBold,
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: driveListRowHorizontalPadding,
        vertical: _stackedGap,
      ),
      child: Row(
        children: [
          heading(appLocalizationsOf(context).name, _nameFlex),
          const SizedBox(width: _columnGap),
          heading(appLocalizationsOf(context).lastSynced, _syncFlex),
          const SizedBox(width: _columnGap),
          heading(appLocalizationsOf(context).driveListFilesHeading, _filesFlex,
              align: true),
          const SizedBox(width: _columnGap),
          heading(appLocalizationsOf(context).size, _sizeFlex, align: true),
          const SizedBox(width: _columnGap),
          heading(appLocalizationsOf(context).dateCreated, _createdFlex),
          // The rows' menu gutter, so the headings sit over their own columns.
          const SizedBox(width: driveListMenuGutter),
        ],
      ),
    );
  }
}

/// One drive, as a row on a wide screen and a stacked card on a narrow one.
class DriveListRow extends StatelessWidget {
  const DriveListRow({
    super.key,
    required this.drive,
    required this.onTap,
    required this.showsColumns,
    this.menu,
  });

  final DriveListItem drive;
  final VoidCallback onTap;

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

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return _HoverHighlight(
      colour: colorTokens.containerL1,
      child: Container(
        // A hairline under every row is what made this read as a spreadsheet
        // where every other table reads as a panel: the explorer separates its
        // rows with the card ground and hover alone, and draws no lines at
        // all. Inside the panel this list now sits in, the same holds here.
        //
        // The stacked layout keeps its lines. There the row is a block of
        // wrapped text rather than a line of cells, and without a rule between
        // them two drives run together - which is why the explorer's own phone
        // view separates its tiles too, by a gap rather than by nothing.
        decoration: showsColumns
            ? null
            : BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colorTokens.strokeLow),
                ),
              ),
        // The menu sits beside the row's content rather than inside it, so the
        // tap that opens the drive and the tap that opens the menu are two
        // targets rather than one on top of the other - and so the menu's own
        // height is bounded by the row instead of setting it. A phone's row is
        // the stacked card, which is taller than the target either way.
        child: Row(
          children: [
            Expanded(
              child: ArDriveClickArea(
                child: Semantics(
                  button: true,
                  label: drive.name,
                  child: InkWell(
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: driveListRowHorizontalPadding,
                        vertical: _rowVerticalPadding,
                      ),
                      child:
                          showsColumns ? _columns(context) : _stacked(context),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: driveListMenuGutter,
              // `heightFactor: 1` so the gutter is as tall as the menu and no
              // taller. A plain Center fills whatever height it is offered, and
              // in any box with a bounded height - which is most of them outside
              // a sliver - that made the gutter set the row's height instead of
              // fitting inside it.
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

  Widget _columns(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: _nameFlex, child: _name(context)),
        const SizedBox(width: _columnGap),
        Expanded(flex: _syncFlex, child: _syncState(context)),
        const SizedBox(width: _columnGap),
        Expanded(flex: _filesFlex, child: _files(context, align: true)),
        const SizedBox(width: _columnGap),
        Expanded(flex: _sizeFlex, child: _size(context, align: true)),
        const SizedBox(width: _columnGap),
        Expanded(flex: _createdFlex, child: _created(context)),
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
            // already says "Never synced", which is the same fact in words.
            if (drive.fileCount != null) _files(context, align: false),
            if (drive.totalSize != null) _size(context, align: false),
            _created(context),
          ],
        ),
      ],
    );
  }

  Widget _name(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Public or private, said with the same icon the rest of the app uses
        // for it rather than a word this row has no space for.
        Tooltip(
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
        const SizedBox(width: _badgeGap),
        // The name and the badge together, allowed to become two lines.
        //
        // The badge was a rigid child of this row, so the name - the only
        // thing that says *which* drive this is - was the one that gave: at
        // 320px it collapsed to zero width and vanished while the badge ran
        // off the screen, from about 1.1x text scale. Ordinary browser zoom,
        // not an accessibility extreme. `_stacked()` already wraps the figures
        // below for the same reason; this row never got the same treatment.
        Flexible(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: _badgeGap,
            runSpacing: 2,
            children: [
              Text(
                drive.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typography.paragraphNormal(
                  color: colorTokens.textHigh,
                  fontWeight: ArFontWeight.semiBold,
                ),
              ),
              if (drive.isSharedWithMe) _SharedMarker(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _syncState(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    // A failure is drawn as one. The top bar reports "2 of 12 drives could not
    // be synced" in red with a triangle and sends the reader here to find out
    // which - and this said so in the same grey as "Synced 5 minutes ago", so
    // the one row that needed finding looked like every row that did not.
    // The same 14px triangle the sync history uses, so the two agree.
    if (drive.lastSyncFailed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ArDriveIcons.triangle(size: 14, color: colorTokens.strokeRed),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              formatDriveSyncState(context, drive),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: typography.paragraphSmall(color: colorTokens.textRed),
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

  Widget _files(BuildContext context, {required bool align}) {
    final fileCount = drive.fileCount;

    return _figure(
      context,
      fileCount == null
          ? driveListWithheldFigure
          : appLocalizationsOf(context).driveFileCount(fileCount),
      withheld: fileCount == null,
      align: align,
    );
  }

  Widget _size(BuildContext context, {required bool align}) {
    final totalSize = drive.totalSize;

    return _figure(
      context,
      // Withheld until the drive has been walked. `SUM(size)` counts synced
      // rows only, so an unsynced drive reads as 0 B - which is worse than
      // saying nothing, because it looks like an answer.
      totalSize == null ? driveListWithheldFigure : filesize(totalSize),
      withheld: totalSize == null,
      align: align,
    );
  }

  Widget _created(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Text(
      appLocalizationsOf(context)
          .driveCreatedOnDate(DateFormat.yMMMd().format(drive.dateCreated)),
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
    required bool align,
  }) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    final label = Text(
      text,
      // Right-aligned in the tabular layout so the digits line up down the
      // column; left-aligned when the row is stacked and there is no column
      // to line up with.
      textAlign: align ? TextAlign.end : TextAlign.start,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: typography
          .paragraphSmall(
        color: withheld ? colorTokens.textXLow : colorTokens.textMid,
      )
          .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    );

    if (!withheld) {
      return label;
    }

    return Tooltip(
      message: appLocalizationsOf(context).notKnownUntilSynced,
      child: label,
    );
  }
}

/// Says a drive belongs to somebody else, in place rather than in a section of
/// its own.
class _SharedMarker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: _badgeGap, vertical: 2),
      decoration: BoxDecoration(
        color: colorTokens.containerL3,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        appLocalizationsOf(context).driveSharedWithMe,
        style: typography.paragraphSmall(color: colorTokens.textMid),
      ),
    );
  }
}

/// What the row says about when this drive was last read.
///
/// Pulled out of the widget so the thresholds can be checked directly. Every
/// branch is a different fact, and none of them is allowed to stand in for
/// another: "Never synced" is not "empty", and a bare "Synced" is not a time.
String formatDriveSyncState(
  BuildContext context,
  DriveListItem drive, {
  DateTime? now,
}) {
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
      .driveSyncedOnDate(DateFormat.yMMMd().format(lastSyncedAt));
}

/// Paints a row's hover state.
///
/// A row that opens a drive when clicked should look like one. The row uses an
/// `InkWell` for its tap, and an InkWell's hover needs a `Material` ancestor
/// that a table built out of Containers does not provide - so nothing ever
/// painted. This owns the state so the row itself can stay stateless.
class _HoverHighlight extends StatefulWidget {
  const _HoverHighlight({required this.colour, required this.child});

  final Color colour;
  final Widget child;

  @override
  State<_HoverHighlight> createState() => _HoverHighlightState();
}

class _HoverHighlightState extends State<_HoverHighlight> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: ColoredBox(
        color: _isHovering ? widget.colour : Colors.transparent,
        child: widget.child,
      ),
    );
  }
}

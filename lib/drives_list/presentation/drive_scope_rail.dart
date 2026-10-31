import 'package:ardrive/drives_list/domain/drive_scope.dart';
import 'package:ardrive/drives_list/presentation/drives_list_cubit.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// What the sidebar shows while the drives list is the page.
///
/// The sidebar used to list every drive here, beside a table listing every
/// drive - the same names in the same order with less information, and Private
/// and Shared pushed below however many public drives the wallet had, so they
/// were off screen on any real account.
///
/// The section headings were the only part of that carrying navigation. They
/// are the navigation now, and the names stay in the table where they have
/// columns to explain themselves. Short, fixed height, nothing to scroll.
class DriveScopeRail extends StatelessWidget {
  const DriveScopeRail({super.key, required this.showLabels});

  /// False on the collapsed desktop rail, where the icon carries it alone.
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DrivesListCubit, DrivesListState>(
      builder: (context, state) {
        final counts = state is DrivesListLoaded ? state.counts : null;
        final current =
            state is DrivesListLoaded ? state.scope : DriveScope.all;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // `all` is not here: the sidebar draws it above this rail, on
            // every screen, so the top of the nav never changes as the reader
            // moves between the list and a drive.
            for (final scope in DriveScope.values)
              if (scope != DriveScope.all)
                // A scope nobody has anything in is not offered. Hidden is the
                // one worth suppressing: most wallets have none, and an empty
                // row invites a click that shows an empty table.
                if (scope != DriveScope.hidden || (counts?[scope] ?? 0) > 0)
                  DriveNavRow(
                    icon: iconFor(scope),
                    label: labelFor(context, scope),
                    count: counts?[scope],
                    isCurrent: scope == current,
                    showLabel: showLabels,
                    onTap: () {
                      // On a phone the drawer closes, as it does for every
                      // other nav row: left open it covered the list the tap
                      // just changed.
                      if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                        Scaffold.of(context).closeDrawer();
                      }
                      context.read<DrivesListCubit>().showScope(scope);
                    },
                  ),
          ],
        );
      },
    );
  }

  static String labelFor(BuildContext context, DriveScope scope) {
    final l = appLocalizationsOf(context);

    switch (scope) {
      case DriveScope.all:
        return l.yourDrives;
      case DriveScope.public:
        return l.publicDrives;
      case DriveScope.private:
        return l.privateDrives;
      case DriveScope.sharedWithMe:
        // The row tag's words too, so the scope has one name, and not one
        // that reads as drives I shared.
        return l.driveSharedWithMe;
      case DriveScope.hidden:
        return l.hiddenDrives;
    }
  }

  /// Plain icons, one meaning each: the same globe, lock and people that
  /// name a drive's kind elsewhere, and ArDrive's own hide eye.
  static IconData iconFor(DriveScope scope) {
    switch (scope) {
      case DriveScope.all:
        return Icons.home_outlined;
      // Plain, one meaning each, as the marks in the rows draw them.
      case DriveScope.public:
        return ArDriveIcons.publicDrive().icon;
      case DriveScope.private:
        return ArDriveIcons.privateDrive().icon;
      case DriveScope.sharedWithMe:
        return ArDriveIcons.sharedDrive().icon;
      case DriveScope.hidden:
        return ArDriveIcons.eyeClosed().icon;
    }
  }
}

/// One row of the nav, wherever it appears.
///
/// Shared so the permanent "Your drives" anchor the sidebar draws above this
/// rail is the same object as the scopes below it - the row a reader relies on
/// to get home must not be a lookalike that drifts.
class DriveNavRow extends StatelessWidget {
  const DriveNavRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.count,
    this.isCurrent = false,
    this.showLabel = true,
    this.trailing,
    this.isMuted = false,
    this.dense = false,
    this.isExpanded,
    this.onToggle,
  });

  /// Null for a row that belongs to the row above it - a drive under its
  /// Public or Private heading. The icon's width is still kept, so the
  /// drive's name starts where the heading's words do.
  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  final int? count;
  final bool isCurrent;
  final bool showLabel;

  /// Drawn at the far end: a heading's chevron, a drive's hidden or alert
  /// mark.
  final Widget? trailing;

  /// A hidden drive: there, but quieter.
  final bool isMuted;

  /// Less height, for the drives listed under a heading. Same grid, same
  /// highlight; a long list of drives just takes less room.
  final bool dense;

  /// For a row that opens and closes the rows under it: whether they are
  /// showing, said to a screen reader. Null for every other row.
  final bool? isExpanded;

  /// For a heading whose words go somewhere: the chevron alone opens and
  /// closes the rows under it, as its own button. Null when the whole row
  /// toggles, or nothing does.
  final VoidCallback? onToggle;

  /// The icon's size, and the space a row without one keeps for it.
  static const iconSize = 18.0;

  /// A full row's height: the touch target.
  static const navRowHeight = 40.0;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    // Lit the way a selected drive row is, so "where am I" reads the same
    // whichever of the two the sidebar is showing.
    final color = isCurrent
        ? colorTokens.textHigh
        : isMuted
            ? colorTokens.textLow
            : colorTokens.textMid;

    return HoverWidget(
      tooltip: showLabel ? '' : label,
      child: ArDriveClickArea(
        child: Semantics(
          button: true,
          selected: isCurrent,
          // Said by the chevron instead when it is a button of its own.
          expanded: onToggle == null ? isExpanded : null,
          // Tab reaches every scope, not only the first; Enter or Space
          // opens it.
          child: ArDriveFocusable(
            onActivate: onTap,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Container(
                // The table's selected-row colour, so the nav and the table
                // mark where you are alike. containerL2 was about 1.1:1
                // against the page in dark.
                decoration: isCurrent
                    ? BoxDecoration(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .tableTheme
                            .selectedItemColor,
                        borderRadius: BorderRadius.circular(ArDriveRadius.sm),
                      )
                    : null,
                // A full row is the 40 px touch target at any label length;
                // a dense row, a drive under its heading, is its label's
                // height with the scale's smallest step either side.
                constraints:
                    BoxConstraints(minHeight: dense ? 0 : navRowHeight),
                padding: const EdgeInsets.symmetric(
                  horizontal: ArDriveSpacing.sm,
                  vertical: ArDriveSpacing.xxs,
                ),
                child: Row(
                  mainAxisAlignment: showLabel
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.center,
                  children: [
                    if (icon == null)
                      const SizedBox(width: iconSize)
                    else
                      Icon(icon, size: iconSize, color: color),
                    if (showLabel) ...[
                      const SizedBox(width: ArDriveSpacing.xs),
                      // Wraps rather than ellipsizes, like the drive names that
                      // used to be here: at a large text scale a clipped scope is
                      // a destination the reader cannot identify.
                      Expanded(
                        child: Text(
                          label,
                          // SemiBold, like every label: Bold is for titles, and
                          // the fill already marks the current row.
                          style: typography.paragraphNormal(
                            color: color,
                            fontWeight: ArFontWeight.semiBold,
                          ),
                        ),
                      ),
                      if (count != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '$count',
                          style: typography
                              .paragraphSmall(
                            color: colorTokens.textLow,
                          )
                              .copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                      if (trailing != null) ...[
                        const SizedBox(width: 8),
                        trailing!,
                      ],
                      if (onToggle != null) ...[
                        const SizedBox(width: 4),
                        _Chevron(
                          key: ValueKey('nav-toggle-$label'),
                          section: label,
                          isExpanded: isExpanded ?? false,
                          onToggle: onToggle!,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A heading's chevron as a button of its own: the heading's words open its
/// page, and this opens and closes the rows under it.
class _Chevron extends StatelessWidget {
  const _Chevron({
    super.key,
    required this.section,
    required this.isExpanded,
    required this.onToggle,
  });

  final String section;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final strings = appLocalizationsOf(context);

    return Semantics(
      container: true,
      button: true,
      expanded: isExpanded,
      label: isExpanded
          ? strings.navCollapseSection(section)
          : strings.navExpandSection(section),
      excludeSemantics: true,
      // A button of its own: Tab reaches it and Enter or Space folds the
      // section, now that tapping the heading opens its page. Twice the
      // arrow's width and the label's line height, so it is easy to hit
      // without making the row taller.
      child: ArDriveFocusable(
        onActivate: onToggle,
        // The ink well's hover and ripple stay for a mouse; its own focus,
        // a faint tint, gives way to the ring.
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            canRequestFocus: false,
            onTap: onToggle,
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 32,
              height: 24,
              child: Center(
                child: AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: ArDriveIcons.chevronDown(
                      size: 16, color: colorTokens.textMid),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

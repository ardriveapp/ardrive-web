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
                    onTap: () =>
                        context.read<DrivesListCubit>().showScope(scope),
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
        return l.allDrivesScope;
      case DriveScope.public:
        return l.publicDrives;
      case DriveScope.private:
        return l.privateDrives;
      case DriveScope.sharedWithMe:
        return l.sharedDrives;
      case DriveScope.hidden:
        return l.hiddenDrives;
    }
  }

  static IconData iconFor(DriveScope scope) {
    switch (scope) {
      case DriveScope.all:
        return Icons.home_outlined;
      case DriveScope.public:
        return Icons.public_outlined;
      case DriveScope.private:
        return Icons.lock_outline;
      case DriveScope.sharedWithMe:
        return Icons.swap_horiz_outlined;
      case DriveScope.hidden:
        return Icons.visibility_off_outlined;
    }
  }
}

/// One row of the nav, wherever it appears.
///
/// Shared so the permanent "All drives" anchor the sidebar draws above this
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
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int? count;
  final bool isCurrent;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    // Lit the way a selected drive row is, so "where am I" reads the same
    // whichever of the two the sidebar is showing.
    final color = isCurrent ? colorTokens.textHigh : colorTokens.textMid;

    return HoverWidget(
      tooltip: showLabel ? '' : label,
      child: ArDriveClickArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            decoration: isCurrent
                ? BoxDecoration(
                    color: colorTokens.containerL2,
                    borderRadius: BorderRadius.circular(4),
                  )
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              mainAxisAlignment: showLabel
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: color),
                if (showLabel) ...[
                  const SizedBox(width: 10),
                  // Wraps rather than ellipsizes, like the drive names that
                  // used to be here: at a large text scale a clipped scope is
                  // a destination the reader cannot identify.
                  Expanded(
                    child: Text(
                      label,
                      style: typography.paragraphNormal(
                        color: color,
                        fontWeight: isCurrent
                            ? ArFontWeight.bold
                            : ArFontWeight.semiBold,
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
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:ardrive/components/drive_attach_form.dart';
import 'package:ardrive/drives_list/domain/drive_scope.dart';
import 'package:ardrive/drives_list/presentation/drive_scope_rail.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// What a scope says when it holds nothing.
///
/// A scope that filters to nothing used to be a dead end: an empty table under
/// a heading, with the action that would fill it nowhere on the page. Shared is
/// the sharp case - attaching is the *only* way a drive gets there, and the
/// only place to attach one was the New menu, which reads as "make something",
/// not "add something somebody sent me".
///
/// The design system's empty state, so it has the icon, spacing and phone
/// gutter every other empty state has. Its action is secondary: the sidebar's
/// New is the view's one primary.
class DriveScopeEmpty extends StatelessWidget {
  const DriveScopeEmpty({
    super.key,
    required this.scope,
    this.hiddenCount = 0,
  });

  final DriveScope scope;

  /// How many drives are hidden. Your drives leaves hidden drives out, so a
  /// wallet whose drives are all hidden lands here, and is told where they
  /// went rather than that it has none.
  final int hiddenCount;

  bool get _allHidden => scope == DriveScope.all && hiddenCount > 0;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final l = appLocalizationsOf(context);

    // Scrolls rather than overflows on a short screen, and centres itself in
    // the height there is.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: ArDriveEmptyState(
            icon: Icon(
              _allHidden
                  ? DriveScopeRail.iconFor(DriveScope.hidden)
                  : DriveScopeRail.iconFor(scope),
              size: 32,
              color: colorTokens.iconLow,
            ),
            title: _title(l),
            message: _description(l),
            secondaryActionLabel:
                scope == DriveScope.sharedWithMe ? l.attachDrive : null,
            onSecondaryAction: scope == DriveScope.sharedWithMe
                ? () => attachDrive(context: context)
                : null,
          ),
        ),
      ),
    );
  }

  String _title(AppLocalizations l) {
    switch (scope) {
      case DriveScope.public:
        return l.noPublicDrives;
      case DriveScope.private:
        return l.noPrivateDrives;
      case DriveScope.sharedWithMe:
        return l.noSharedDrives;
      case DriveScope.hidden:
        return l.noHiddenDrives;
      case DriveScope.all:
        return _allHidden ? l.allDrivesHidden : l.noDrivesInScope;
    }
  }

  String? _description(AppLocalizations l) {
    switch (scope) {
      case DriveScope.public:
        return l.noPublicDrivesDescription;
      case DriveScope.private:
        return l.noPrivateDrivesDescription;
      case DriveScope.sharedWithMe:
        return l.noSharedDrivesDescription;
      case DriveScope.hidden:
        return l.noHiddenDrivesDescription;
      case DriveScope.all:
        return _allHidden ? l.allDrivesHiddenDescription : null;
    }
  }
}

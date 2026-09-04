import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:ardrive/components/drive_attach_form.dart';
import 'package:ardrive/drives_list/domain/drive_scope.dart';
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
class DriveScopeEmpty extends StatelessWidget {
  const DriveScopeEmpty({super.key, required this.scope});

  final DriveScope scope;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final l = appLocalizationsOf(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _title(l),
              // The same step every other state of this page uses. The one that
              // read `heading2` was louder than the page's own title.
              style: typography.heading4(
                color: colorTokens.textHigh,
                fontWeight: ArFontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _description(l),
              style: typography.paragraphNormal(color: colorTokens.textMid),
              textAlign: TextAlign.center,
            ),
            if (scope == DriveScope.sharedWithMe) ...[
              const SizedBox(height: 24),
              ArDriveButtonNew(
                text: l.attachDrive,
                typography: typography,
                variant: ButtonVariant.primary,
                maxWidth: 220,
                maxHeight: 40,
                onPressed: () => attachDrive(context: context),
              ),
            ],
          ],
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
      case DriveScope.all:
      case DriveScope.hidden:
        return l.noDrivesInScope;
    }
  }

  String _description(AppLocalizations l) {
    switch (scope) {
      case DriveScope.public:
        return l.noPublicDrivesDescription;
      case DriveScope.private:
        return l.noPrivateDrivesDescription;
      case DriveScope.sharedWithMe:
        return l.noSharedDrivesDescription;
      case DriveScope.all:
      case DriveScope.hidden:
        return l.noSharedDrivesDescription;
    }
  }
}

import 'dart:math' as math;

import 'package:ardrive/models/models.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// The folder list a picker dialog shows: the folder in view, its subfolders
/// to open and its files, greyed, for context. Move and Recreate folder both
/// use it, inside [ArDriveStandardModalNew]'s content.
///
/// While [enabled] is false (the dialog's work is running) nothing opens.
class FolderPickerBody extends StatelessWidget {
  const FolderPickerBody({
    super.key,
    required this.folders,
    required this.fileNames,
    required this.atRoot,
    required this.isFolderEnabled,
    required this.onOpenFolder,
    required this.onBack,
    required this.onCreateFolder,
    this.enabled = true,
  });

  final List<FolderEntry> folders;
  final List<String> fileNames;
  final bool atRoot;
  final bool Function(FolderEntry folder) isFolderEnabled;
  final void Function(String folderId) onOpenFolder;
  final VoidCallback onBack;
  final VoidCallback onCreateFolder;
  final bool enabled;

  /// The most the list is tall; a short window gets less.
  static const double maxListHeight = 320;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final l10n = appLocalizationsOf(context);
    final listHeight = math.min(
      maxListHeight,
      MediaQuery.sizeOf(context).height * 0.4,
    );

    TextStyle rowStyle({required bool enabled}) => typography.paragraphLarge(
          color: enabled ? colorTokens.textHigh : colorTokens.textXLow,
        );

    Widget row({
      required Widget icon,
      required String name,
      required bool rowEnabled,
      Widget? trailing,
      VoidCallback? onTap,
    }) {
      final child = Padding(
        padding: const EdgeInsets.symmetric(vertical: ArDriveSpacing.sm),
        child: Row(
          children: [
            icon,
            const SizedBox(width: ArDriveSpacing.xs),
            Expanded(
              child: Text(
                name,
                style: rowStyle(enabled: rowEnabled),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      );
      if (onTap == null) return child;
      return Semantics(
        button: true,
        container: true,
        excludeSemantics: true,
        label: name,
        onTap: onTap,
        child: ArDriveFocusable(
          onActivate: onTap,
          child: ArDriveClickArea(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: child,
            ),
          ),
        ),
      );
    }

    final items = <Widget>[
      ...folders.map((f) {
        final folderEnabled = isFolderEnabled(f);
        final iconColor =
            folderEnabled ? colorTokens.iconMid : colorTokens.textXLow;
        return row(
          icon: ArDriveIcons.folderOutline(size: 16, color: iconColor),
          name: f.name,
          rowEnabled: folderEnabled,
          trailing: ArDriveIcons.carretRight(size: 18, color: iconColor),
          onTap: folderEnabled && enabled ? () => onOpenFolder(f.id) : null,
        );
      }),
      ...fileNames.map(
        (name) => row(
          icon: ArDriveIcons.fileOutlined(
            size: 16,
            color: colorTokens.textXLow,
          ),
          name: name,
          rowEnabled: false,
        ),
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!atRoot)
          Semantics(
            button: true,
            container: true,
            excludeSemantics: true,
            label: l10n.back,
            onTap: enabled ? onBack : null,
            child: ArDriveFocusable(
              onActivate: enabled ? onBack : null,
              child: ArDriveClickArea(
                showCursor: enabled,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: enabled ? onBack : null,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: ArDriveSpacing.xs),
                    child: Row(children: [
                      ArDriveIcons.arrowLeft(
                        size: 18,
                        color: colorTokens.iconMid,
                      ),
                      const SizedBox(width: ArDriveSpacing.xs),
                      Text(l10n.back, style: rowStyle(enabled: true)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        SizedBox(
          height: listHeight,
          child: ArDriveScrollBar(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (context, index) => items[index],
            ),
          ),
        ),
        Divider(color: colorTokens.strokeLow, height: 1),
        const SizedBox(height: ArDriveSpacing.sm),
        ArDriveButtonNew(
          variant: ButtonVariant.outline,
          size: ArDriveButtonSize.compact,
          typography: typography,
          isDisabled: !enabled,
          icon: ArDriveIcons.iconNewFolder1(
            size: 16,
            color: colorTokens.textLink,
          ),
          text: l10n.createFolderEmphasized,
          onPressed: onCreateFolder,
        ),
      ],
    );
  }
}

/// The picker dialog's width: a large dialog, and no wider than the screen.
double folderPickerWidth(BuildContext context) {
  final screenWidth = MediaQuery.sizeOf(context).width;
  return screenWidth < kLargeDialogWidth + 32
      ? screenWidth - 32
      : kLargeDialogWidth;
}

import 'package:ardrive/components/drive_picker/drive_picker_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart'
    show getIconForContentType;
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// What the drive picker was closed on: the folder in view, and the file
/// chosen in it where files can be chosen.
typedef DrivePickerChoice = ({
  Drive drive,
  DrivePickerFolder folder,
  String? fileId,
});

/// Opens the drive picker: the user's [drives], walked a folder at a time as
/// Move walks them, to choose where something goes or what to act on.
///
/// It opens on [driveId]'s [folderId] (the root when null), or on the list
/// of drives. [canChooseFile] lets files be chosen; without it they are
/// shown greyed, for context, and only a folder can be chosen.
/// [actionLabel] names the main action for what is chosen. [onChoose] runs
/// once the picker has closed, in the same press, so a browser still lets
/// it open a file picker.
Future<void> showDrivePicker(
  BuildContext context, {
  required String title,
  required List<Drive> drives,
  required String Function(DrivePickerState state) actionLabel,
  required void Function(DrivePickerChoice choice) onChoose,
  String? driveId,
  String? folderId,
  bool Function(DrivePickerEntry file)? canChooseFile,
  bool showsPrivacy = false,
  String? noDrivesMessage,
  DrivePickerRead? read,
}) {
  final cubit = DrivePickerCubit(
    drives: drives,
    read: read ?? drivePickerReadFrom(context.read<DriveDao>()),
  )..start(driveId: driveId, folderId: folderId);
  return showArDriveDialog(
    context,
    content: BlocProvider.value(
      value: cubit,
      child: DrivePickerDialog(
        title: title,
        actionLabel: actionLabel,
        onChoose: onChoose,
        canChooseFile: canChooseFile,
        showsPrivacy: showsPrivacy,
        noDrivesMessage: noDrivesMessage,
      ),
    ),
  ).whenComplete(cubit.close);
}

/// The drive picker's dialog, over a [DrivePickerCubit]. See
/// [showDrivePicker].
class DrivePickerDialog extends StatelessWidget {
  const DrivePickerDialog({
    super.key,
    required this.title,
    required this.actionLabel,
    required this.onChoose,
    this.canChooseFile,
    this.showsPrivacy = false,
    this.noDrivesMessage,
  });

  final String title;
  final String Function(DrivePickerState state) actionLabel;
  final void Function(DrivePickerChoice choice) onChoose;
  final bool Function(DrivePickerEntry file)? canChooseFile;

  /// Says on each drive whether it is public or private: for an upload,
  /// which cannot be taken back.
  final bool showsPrivacy;

  /// Said when there are no drives to choose from.
  final String? noDrivesMessage;

  /// The list keeps one height as the picker moves between folders.
  static const listHeight = 320.0;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final cubit = context.watch<DrivePickerCubit>();
    final state = cubit.state;
    final folder = state.folder;

    void choose() {
      final drive = state.drive;
      if (drive == null || folder == null) return;
      Navigator.of(context).pop();
      onChoose((drive: drive, folder: folder, fileId: state.fileId));
    }

    return ArDriveStandardModalNew(
      title: title,
      width: kMediumDialogWidth,
      scrollableContent: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Location(state: state, onBack: cubit.back),
          const SizedBox(height: ArDriveSpacing.xs),
          SizedBox(
            height: listHeight,
            child: _Contents(
              state: state,
              canChooseFile: canChooseFile,
              showsPrivacy: showsPrivacy,
              noDrivesMessage: noDrivesMessage,
            ),
          ),
        ],
      ),
      actions: [
        ModalAction.dismiss(
          action: () => Navigator.of(context).pop(),
          title: strings.cancel,
        ),
        ModalAction(
          action: choose,
          title: actionLabel(state),
          isEnable: folder != null,
        ),
      ],
    );
  }
}

/// Where the picker is: the drives, or a drive's folder, with Back.
class _Location extends StatelessWidget {
  const _Location({required this.state, required this.onBack});

  final DrivePickerState state;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final drive = state.drive;
    final folder = state.folder;
    final name = drive == null
        ? strings.yourDrives
        : (folder == null || state.atRoot)
            ? drive.name
            : folder.name;

    return SizedBox(
      height: 40,
      child: Row(
        children: [
          if (drive != null) ...[
            ArDriveIconButton(
              tooltip: strings.back,
              icon: ArDriveIcons.arrowLeft(size: 20, color: colors.iconMid),
              onPressed: onBack,
            ),
            const SizedBox(width: ArDriveSpacing.xs),
          ],
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typography.paragraphLarge(
                  color: colors.textHigh,
                  fontWeight: ArFontWeight.semiBold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Contents extends StatelessWidget {
  const _Contents({
    required this.state,
    required this.canChooseFile,
    required this.showsPrivacy,
    required this.noDrivesMessage,
  });

  final DrivePickerState state;
  final bool Function(DrivePickerEntry file)? canChooseFile;
  final bool showsPrivacy;
  final String? noDrivesMessage;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final cubit = context.read<DrivePickerCubit>();

    if (state.choosingDrive) {
      if (state.drives.isEmpty) {
        return _Message(noDrivesMessage ?? strings.noPublicDrives);
      }
      return ListView(
        children: [
          for (final drive in state.drives)
            DrivePickerRow(
              icon: drive.isPrivate
                  ? ArDriveIcons.privateDrive(size: 20)
                  : ArDriveIcons.publicDrive(size: 20),
              title: drive.name,
              trailing: showsPrivacy
                  ? (drive.isPrivate ? strings.private : strings.public)
                  : null,
              opens: true,
              onTap: () => cubit.openDrive(drive),
            ),
        ],
      );
    }

    if (state.loading) {
      return const Center(
        child: ArDriveSpinner(size: ArDriveSpinnerSize.large),
      );
    }

    final folder = state.folder;
    if (folder == null) return _Message(strings.driveNeverSynced);
    if (folder.folders.isEmpty && folder.files.isEmpty) {
      return _Message(strings.drivePickerEmptyFolder);
    }

    return ListView(
      children: [
        for (final entry in folder.folders)
          DrivePickerRow(
            icon: getIconForContentType('folder', size: 20),
            title: entry.name,
            opens: true,
            onTap: () => cubit.openFolder(entry.id),
          ),
        for (final entry in folder.files)
          DrivePickerRow(
            icon: getIconForContentType(entry.contentType, size: 20),
            title: entry.name,
            enabled: canChooseFile?.call(entry) ?? false,
            selected: state.fileId == entry.id,
            onTap: () => cubit.chooseFile(entry.id),
          ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ArDriveSpacing.sm),
      child: Text(
        text,
        style: ArDriveTypographyNew.of(context)
            .paragraphNormal(color: colors.textMid),
      ),
    );
  }
}

/// One drive, folder or file in the picker: a button, reachable with Tab and
/// announced with its name. A row that [opens] leads into it; a file row is
/// chosen, and shows it.
class DrivePickerRow extends StatelessWidget {
  const DrivePickerRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.trailing,
    this.opens = false,
    this.enabled = true,
    this.selected = false,
  });

  final ArDriveIcon icon;
  final String title;
  final VoidCallback onTap;

  /// A quiet word at the end, such as "Private".
  final String? trailing;
  final bool opens;
  final bool enabled;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = ArDriveTheme.of(context).themeData;
    final colors = theme.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    // Fills made for laying over a dialog, as its secondary buttons are: the
    // explorer's row colours are the dialog's own in the light theme.
    final highlight = colors.buttonSecondaryDefault;
    final fg = enabled ? colors.textHigh : colors.textXLow;

    return Semantics(
      button: enabled,
      selected: selected,
      enabled: enabled,
      child: Material(
        color: selected ? colors.buttonSecondaryHover : Colors.transparent,
        borderRadius: BorderRadius.circular(ArDriveRadius.sm),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(ArDriveRadius.sm),
          hoverColor: highlight,
          focusColor: highlight,
          highlightColor: highlight,
          splashFactory: NoSplash.splashFactory,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ArDriveSpacing.xs,
                vertical: ArDriveSpacing.xxs,
              ),
              child: Row(
                children: [
                  ArDriveIcon(
                    icon: icon.icon,
                    size: icon.size,
                    color: enabled ? colors.iconMid : colors.textXLow,
                  ),
                  const SizedBox(width: ArDriveSpacing.sm),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typography.paragraphNormal(
                        color: fg,
                        fontWeight: selected
                            ? ArFontWeight.bold
                            : ArFontWeight.semiBold,
                      ),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: ArDriveSpacing.sm),
                    Text(
                      trailing!,
                      style: typography.paragraphSmall(color: colors.textMid),
                    ),
                  ],
                  // Not by colour alone: a chosen file is ticked.
                  if (selected) ...[
                    const SizedBox(width: ArDriveSpacing.xs),
                    ArDriveIcons.checkmark(size: 18, color: colors.iconHigh),
                  ],
                  if (opens) ...[
                    const SizedBox(width: ArDriveSpacing.xs),
                    ArDriveIcons.carretRight(size: 18, color: colors.iconMid),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

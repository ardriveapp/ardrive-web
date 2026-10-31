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
import 'package:flutter/services.dart';
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
/// of drives. [purpose] decides which folders are offered (see
/// [DrivePickerPurpose]). [canChooseFile] lets files be chosen; without it
/// they are shown greyed, for context, and only a folder can be chosen.
/// [actionLabel] names the main action for what is chosen. [onChoose] runs
/// once the picker has closed, in the same press, so a browser still lets
/// it open a file picker. [sync] lets a drive this device has not read be
/// synced from the picker, as opening it from Your drives does.
/// [showsPrivacy] says, on each drive and on the place in view, whether it is
/// public or private.
Future<void> showDrivePicker(
  BuildContext context, {
  required String title,
  required List<Drive> drives,
  required DrivePickerPurpose purpose,
  required String Function(DrivePickerState state) actionLabel,
  required void Function(DrivePickerChoice choice) onChoose,
  String? driveId,
  String? folderId,
  bool Function(DrivePickerEntry file)? canChooseFile,
  bool showsPrivacy = false,
  String? noDrivesMessage,
  Future<bool> Function(Drive drive)? sync,
  DrivePickerRead? read,
}) {
  final cubit = DrivePickerCubit(
    drives: drives,
    read:
        read ?? drivePickerReadFrom(context.read<DriveDao>(), purpose: purpose),
    sync: sync,
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
class DrivePickerDialog extends StatefulWidget {
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

  /// Says on each drive, and on the place in view, whether it is public or
  /// private: for an upload, which cannot be taken back.
  final bool showsPrivacy;

  /// Said when there are no drives to choose from.
  final String? noDrivesMessage;

  /// The list keeps one height as the picker moves between folders.
  static const listHeight = 320.0;

  @override
  State<DrivePickerDialog> createState() => _DrivePickerDialogState();
}

class _DrivePickerDialogState extends State<DrivePickerDialog> {
  /// Back, which keeps keyboard focus in the picker once the row that was
  /// pressed has gone with the folder it was in.
  final _backFocus = FocusNode(debugLabel: 'drive picker back');

  @override
  void dispose() {
    _backFocus.dispose();
    super.dispose();
  }

  /// Whether the last press in the picker came from the keyboard.
  bool _byKeyboard = false;

  /// Where the picker is: a change of it moves focus to Back.
  static Object? _place(DrivePickerState state) =>
      (state.drive?.id, state.folder?.id);

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
      widget.onChoose((drive: drive, folder: folder, fileId: state.fileId));
    }

    return BlocListener<DrivePickerCubit, DrivePickerState>(
      listenWhen: (a, b) => _place(a) != _place(b) && b.folder != null,
      listener: (context, state) {
        // The row that was pressed went with the folder it was in, and focus
        // with it: Back keeps a keyboard user in the picker. Not after a
        // click, which would draw a focus ring nobody asked for.
        if (!_byKeyboard) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _backFocus.context != null) _backFocus.requestFocus();
        });
      },
      child: ArDriveStandardModalNew(
        title: widget.title,
        width: kMediumDialogWidth,
        scrollableContent: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DrivePickerLocation(
              state: state,
              onBack: cubit.back,
              showsPrivacy: widget.showsPrivacy,
              backFocus: _backFocus,
            ),
            const SizedBox(height: ArDriveSpacing.xs),
            SizedBox(
              height: DrivePickerDialog.listHeight,
              child: Listener(
                onPointerDown: (_) => _byKeyboard = false,
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        (event.logicalKey == LogicalKeyboardKey.enter ||
                            event.logicalKey ==
                                LogicalKeyboardKey.numpadEnter ||
                            event.logicalKey == LogicalKeyboardKey.space)) {
                      _byKeyboard = true;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: _Contents(
                    state: state,
                    canChooseFile: widget.canChooseFile,
                    showsPrivacy: widget.showsPrivacy,
                    noDrivesMessage: widget.noDrivesMessage,
                  ),
                ),
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
            title: widget.actionLabel(state),
            isEnable: folder != null,
          ),
        ],
      ),
    );
  }
}

/// Where the picker is: the drives, or a drive's folder, with Back. With
/// [showsPrivacy], the drive's icon and whether it is public or private, on
/// its root and in every folder under it. Announced as it changes.
class DrivePickerLocation extends StatelessWidget {
  const DrivePickerLocation({
    super.key,
    required this.state,
    required this.onBack,
    this.showsPrivacy = false,
    this.backFocus,
  });

  final DrivePickerState state;
  final VoidCallback onBack;
  final bool showsPrivacy;
  final FocusNode? backFocus;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final drive = state.drive;
    final folder = state.folder;
    final inFolder = folder != null && !state.atRoot;
    final name = drive == null
        ? strings.yourDrives
        : inFolder
            ? folder.name
            : drive.name;

    Widget? privacy;
    if (showsPrivacy && drive != null) {
      final privacyWord = drive.isPrivate ? strings.private : strings.public;
      privacy = Row(
        children: [
          drive.isPrivate
              ? ArDriveIcons.privateDrive(size: 16, color: colors.iconMid)
              : ArDriveIcons.publicDrive(size: 16, color: colors.iconMid),
          const SizedBox(width: ArDriveSpacing.xxs),
          Flexible(
            child: Text(
              // In a folder, the drive it is in as well.
              inFolder ? '${drive.name}, $privacyWord' : privacyWord,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: typography.paragraphSmall(color: colors.textMid),
            ),
          ),
        ],
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: Row(
        children: [
          if (drive != null) ...[
            ArDriveIconButton(
              tooltip: strings.back,
              focusNode: backFocus,
              icon: ArDriveIcons.arrowLeft(size: 20, color: colors.iconMid),
              onPressed: onBack,
            ),
            const SizedBox(width: ArDriveSpacing.xs),
          ],
          Expanded(
            child: Semantics(
              header: true,
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typography.paragraphLarge(
                      color: colors.textHigh,
                      fontWeight: ArFontWeight.semiBold,
                    ),
                  ),
                  if (privacy != null) privacy,
                ],
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

    if (state.syncing) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const ArDriveSpinner(size: ArDriveSpinnerSize.large),
          const SizedBox(height: ArDriveSpacing.sm),
          _Message(strings.drivePickerSyncing),
        ],
      );
    }

    final folder = state.folder;
    if (folder == null) {
      // A drive this device has not read: sync it here, as opening it from
      // Your drives does, rather than leave a dead end.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Message(state.syncRefused
              ? strings.driveSyncNotStartedAnotherDriveIsSyncing
              : strings.driveNeverSynced),
          if (cubit.canSync)
            ArDriveButtonNew(
              text: strings.sync,
              typography: ArDriveTypographyNew.of(context),
              variant: ButtonVariant.secondary,
              size: ArDriveButtonSize.compact,
              onPressed: cubit.syncDrive,
            ),
        ],
      );
    }
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

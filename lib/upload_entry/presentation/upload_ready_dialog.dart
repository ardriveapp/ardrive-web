import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The last step before the picker: which drive the files are going to.
///
/// It exists because a browser opens a file picker only in direct response to
/// a click, so arriving in a drive cannot open one by itself. That click is
/// worth something here: on permanent storage, whether a drive is public is
/// the choice nobody can take back, and this is the last moment to see it.
///
/// It reports nothing about syncing. A drive that has not been read is the
/// page's business, and the page already tells that story - its own card, its
/// own progress. A second report over the top of it made the reader watch a
/// sync they only wanted as a means to an upload.
///
/// Needs the explorer's [DriveDetailCubit] above it, handed in by
/// `showUploadReadyDialog`, because a dialog does not sit under the page that
/// opened it.
class UploadReadyDialog extends StatefulWidget {
  const UploadReadyDialog({
    super.key,
    required this.drive,
    required this.isFolderUpload,
    required this.onChoose,
  });

  final Drive drive;
  final bool isFolderUpload;

  /// Starts the upload into the folder in view.
  ///
  /// Called after this dialog has closed, but in the same press, so the click
  /// still counts for the picker.
  final void Function(String folderId) onChoose;

  @override
  State<UploadReadyDialog> createState() => _UploadReadyDialogState();
}

class _UploadReadyDialogState extends State<UploadReadyDialog> {
  /// A dialog closes once, and more than one build can call for it.
  bool _closed = false;

  static const _primaryActionWidth = 160.0;

  void _close() {
    if (_closed) {
      return;
    }

    _closed = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final detailState = context.watch<DriveDetailCubit>().state;

    // Only over the drive it was opened for, and only while that drive can
    // still take files. Anything else and the screen has moved on.
    final openHere = detailState is DriveDetailLoadSuccess &&
        detailState.currentDrive.id == widget.drive.id &&
        detailState.hasWritePermissions;

    if (!openHere) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _close();
        }
      });
    }

    final l10n = appLocalizationsOf(context);

    return ArDriveStandardModalNew(
      title: l10n.uploadToDrive(widget.drive.name),
      content: SizedBox(
        width: kMediumDialogWidth,
        child: _Privacy(drive: widget.drive),
      ),
      actions: [
        ModalAction(action: _close, title: l10n.cancel),
        if (openHere)
          ModalAction(
            action: () {
              final folderId = detailState.folderInView.folder.id;

              _close();
              widget.onChoose(folderId);
            },
            title: widget.isFolderUpload
                ? l10n.uploadChooseFolder
                : l10n.uploadChooseFiles,
            customWidth: _primaryActionWidth,
          ),
      ],
    );
  }
}

/// Public or private, with the icon the rest of the app uses for it and the
/// word as well: here it is the thing being decided.
class _Privacy extends StatelessWidget {
  const _Privacy({required this.drive});

  final Drive drive;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final isPrivate = drive.privacy == DrivePrivacyTag.private;

    return Row(
      children: [
        isPrivate
            ? ArDriveIcons.privateDrive(size: 16, color: colorTokens.textMid)
            : ArDriveIcons.publicDrive(size: 16, color: colorTokens.textMid),
        const SizedBox(width: 6),
        Text(
          isPrivate
              ? appLocalizationsOf(context).private
              : appLocalizationsOf(context).public,
          style: typography.paragraphNormal(
            color: colorTokens.textMid,
            fontWeight: ArFontWeight.semiBold,
          ),
        ),
      ],
    );
  }
}

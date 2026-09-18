import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/upload_entry/domain/upload_readiness.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Gets one drive ready for an upload, then hands over to the picker.
///
/// Shown wherever Upload was pressed for a drive that is not open yet. It
/// always names the drive and whether it is public or private before anything
/// is chosen: on permanent storage that is the choice nobody can take back.
///
/// Every state carries its next step. A drive nothing has read offers its
/// sync, a drive being synced shows it, and a drive that is ready offers the
/// picker. The dialog never queues a sync and never starts one on its own.
///
/// Needs the explorer's [DriveDetailCubit] and the app's [SyncCubit] above it.
/// Both are handed in by `showUploadReadyDialog`, because a dialog does not sit
/// under the page that opened it.
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
  /// Called after this dialog has closed, but in the same press: a browser
  /// only opens a file picker in direct response to a click.
  final void Function(String folderId) onChoose;

  @override
  State<UploadReadyDialog> createState() => _UploadReadyDialogState();
}

class _UploadReadyDialogState extends State<UploadReadyDialog> {
  /// A dialog closes once. [UploadReadiness.elsewhere] can be reported by
  /// more than one build before the pop lands.
  bool _closed = false;

  /// The width of the button that moves the upload on, fixed across states so
  /// it does not change size as the drive gets ready.
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
    final syncCubit = context.watch<SyncCubit>();

    final readiness = uploadReadiness(
      driveId: widget.drive.id,
      detailState: detailState,
      syncState: syncCubit.state,
      syncingDriveId: syncCubit.syncingDriveId,
      completedDriveIds: syncCubit.completedDriveIds,
      runDriveIds: syncCubit.syncingDriveIds,
    );

    if (readiness == UploadReadiness.elsewhere) {
      // The screen behind has moved on, so there is nothing true left to say
      // about this drive here.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _close();
        }
      });
    }

    final l10n = appLocalizationsOf(context);
    final name = widget.drive.name;

    return ArDriveStandardModalNew(
      title: l10n.uploadToDrive(name),
      content: SizedBox(
        width: kMediumDialogWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _Privacy(drive: widget.drive),
            if (_message(context, readiness) case final message?) ...[
              const SizedBox(height: 16),
              _Status(
                message: message,
                isWorking: readiness == UploadReadiness.syncing ||
                    readiness == UploadReadiness.opening,
              ),
            ],
          ],
        ),
      ),
      actions: _actions(context, readiness, detailState),
    );
  }

  String? _message(BuildContext context, UploadReadiness readiness) {
    final l10n = appLocalizationsOf(context);
    final name = widget.drive.name;

    return switch (readiness) {
      UploadReadiness.needsSync => l10n.uploadDriveNeedsSync(name),
      UploadReadiness.needsSyncAfterOtherSync =>
        l10n.uploadDriveWaitsForOtherSync(name),
      // The drive's own card says the same thing in the same words.
      UploadReadiness.syncFoundNothing => l10n.driveSyncFoundNothingDescription,
      UploadReadiness.syncing => l10n.uploadDriveSyncing(name),
      UploadReadiness.opening => l10n.uploadDriveOpening(name),
      UploadReadiness.readOnly => l10n.uploadDriveReadOnly(name),
      UploadReadiness.ready || UploadReadiness.elsewhere => null,
    };
  }

  List<ModalAction> _actions(
    BuildContext context,
    UploadReadiness readiness,
    DriveDetailState detailState,
  ) {
    final l10n = appLocalizationsOf(context);

    final chooseTitle = widget.isFolderUpload
        ? l10n.uploadChooseFolder
        : l10n.uploadChooseFiles;

    // Cancel while nothing is running, Close once something is: closing this
    // does not stop a sync, and a button saying Cancel would suggest it does.
    final cancel = ModalAction(action: _close, title: l10n.cancel);
    final close = ModalAction(action: _close, title: l10n.close);

    // Drawn as unavailable rather than left out, so the reader can see what
    // is coming. [ArDriveButtonNew] drops the press while it is disabled, so
    // this action is never called: it is empty only because [ModalAction]
    // requires one.
    ModalAction unavailable(String title) => ModalAction(
          action: () {},
          title: title,
          isEnable: false,
          customWidth: _primaryActionWidth,
        );

    ModalAction sync(String title) => ModalAction(
          action: () => context.read<DriveDetailCubit>().syncCurrentDrive(),
          title: title,
          customWidth: _primaryActionWidth,
        );

    switch (readiness) {
      case UploadReadiness.ready:
        final folderId =
            (detailState as DriveDetailLoadSuccess).folderInView.folder.id;

        return [
          cancel,
          ModalAction(
            action: () {
              _close();
              widget.onChoose(folderId);
            },
            title: chooseTitle,
            customWidth: _primaryActionWidth,
          ),
        ];
      case UploadReadiness.needsSync:
        return [cancel, sync(l10n.syncThisDrive)];
      case UploadReadiness.needsSyncAfterOtherSync:
        return [cancel, unavailable(l10n.syncThisDrive)];
      case UploadReadiness.syncFoundNothing:
        return [close, sync(l10n.checkAgain)];
      case UploadReadiness.syncing:
      case UploadReadiness.opening:
        return [close, unavailable(chooseTitle)];
      case UploadReadiness.readOnly:
      case UploadReadiness.elsewhere:
        return [close];
    }
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

class _Status extends StatelessWidget {
  const _Status({required this.message, required this.isWorking});

  final String message;

  /// Whether something is happening that the reader is waiting on.
  final bool isWorking;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isWorking) ...[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorTokens.textMid,
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            message,
            style: typography.paragraphNormal(color: colorTokens.textHigh),
          ),
        ),
      ],
    );
  }
}

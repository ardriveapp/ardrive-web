import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_bloc.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_event.dart';
import 'package:ardrive/components/create_snapshot_dialog.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/drive_state/presentation/drive_state_creation_modal.dart';
import 'package:ardrive/drive_state/presentation/drive_state_publish_offer.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> promptToSnapshot(
  BuildContext context, {
  required Drive drive,
  required PromptToSnapshotBloc promptToSnapshotBloc,
}) async {
  return showArDriveDialog(
    context,
    content: PromptToSnapshotDialog(
      promptToSnapshotBloc: promptToSnapshotBloc,
      drive: drive,
    ),
  ).then((value) => promptToSnapshotBloc.add(const ClosePromptToSnapshot()));
}

class PromptToSnapshotDialog extends StatefulWidget {
  final PromptToSnapshotBloc promptToSnapshotBloc;

  final Drive drive;

  const PromptToSnapshotDialog({
    super.key,
    required this.drive,
    required this.promptToSnapshotBloc,
  });

  @override
  PromptToSnapshotDialogState createState() => PromptToSnapshotDialogState();
}

class PromptToSnapshotDialogState extends State<PromptToSnapshotDialog> {
  bool _dontAskAgain = false;

  /// The same gate as the drive menu's entry, [driveStatePublishOffer], so
  /// the nudge never offers what the menu would hide: the flag, ownership,
  /// write access and an empty drive all decide it. Anything else keeps the
  /// snapshot nudge.
  bool _offersDriveState(BuildContext context) {
    final profile = context.read<ProfileCubit>().state;
    final detail = context.read<DriveDetailCubit>().state;
    if (profile is! ProfileLoggedIn || detail is! DriveDetailLoadSuccess) {
      return false;
    }
    return driveStatePublishOffer(
          publishingEnabled:
              context.read<ConfigService>().config.enableDriveStatePublishing,
          isDriveOwner: widget.drive.ownerAddress == profile.user.walletAddress,
          hasWritePermissions: detail.hasWritePermissions,
          driveIsEmpty: detail.driveIsEmpty,
        ) ==
        DriveStatePublishOffer.offered;
  }

  @override
  Widget build(BuildContext context) {
    // Where publishing is on, the nudge offers a drive state artifact rather
    // than a snapshot (D14): the same trigger, the same owner-only rule and
    // the same "don't ask again" setting, a different thing to make.
    // Hardcoded English, matching `drive_state_creation_modal.dart`, until
    // the feature's strings move into the `.arb` files in one pass.
    final offersDriveState = _offersDriveState(context);
    final localizations = appLocalizationsOf(context);

    final String title;
    final String body;
    if (offersDriveState) {
      title = _dontAskAgain
          ? 'You won\'t be asked again'
          : 'Make this drive load faster';
      body = _dontAskAgain
          ? 'You can publish this drive\'s state at any time from the '
              'drive\'s menu.'
          : 'This drive takes a while to sync because its history is read '
              'one change at a time. Publishing its state saves the whole '
              'drive as one file on Arweave, so it loads in seconds wherever '
              'you sign in. You see the size and the cost before anything is '
              'uploaded.';
    } else {
      title = _dontAskAgain
          ? localizations.weWontRemindYou
          : localizations.snapshotRecommended;
      body = _dontAskAgain
          ? localizations.snapshotRecommendedDontAskAgain
          : localizations.snapshotRecommendedBody;
    }

    return ArDriveStandardModal(
      hasCloseButton: true,
      title: title,
      content: SizedBox(
        width: kMediumDialogWidth,
        child: Text(
          body,
          style: ArDriveTypography.body.buttonNormalRegular(),
        ),
      ),
      actions: [
        ModalAction(
          action: () {
            if (_dontAskAgain) {
              Navigator.of(context).pop();
            } else {
              setState(() {
                _dontAskAgain = true;
                widget.promptToSnapshotBloc
                    .add(const DismissDontAskAgain(dontAskAgain: true));
              });
            }
          },
          title: _dontAskAgain
              ? localizations.okEmphasized
              : localizations.dontAskMeAgain,
        ),
        if (!_dontAskAgain)
          ModalAction(
            action: () {
              Navigator.of(context).pop();
              if (offersDriveState) {
                promptToCreateDriveState(context, drive: widget.drive);
              } else {
                promptToCreateSnapshot(context, widget.drive);
              }
            },
            title: offersDriveState
                ? 'Publish drive state'
                : localizations.createSnapshot,
          ),
      ],
    );
  }
}

import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_bloc.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_event.dart';
import 'package:ardrive/components/create_snapshot_dialog.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

Future<void> promptToSnapshot(
  BuildContext context, {
  required Drive drive,
  required PromptToSnapshotBloc promptToSnapshotBloc,
}) async {
  // Decided once, before the prompt opens, so its wording cannot disagree
  // with the snapshot its button goes on to create.
  final offersDriveState = await createsDriveStateSnapshot(context, drive);
  if (!context.mounted) {
    promptToSnapshotBloc.add(const ClosePromptToSnapshot());
    return;
  }

  return showArDriveDialog(
    context,
    content: PromptToSnapshotDialog(
      promptToSnapshotBloc: promptToSnapshotBloc,
      drive: drive,
      offersDriveState: offersDriveState,
    ),
  ).then((value) => promptToSnapshotBloc.add(const ClosePromptToSnapshot()));
}

class PromptToSnapshotDialog extends StatefulWidget {
  final PromptToSnapshotBloc promptToSnapshotBloc;

  final Drive drive;

  /// Whether the snapshot offered is a drive state artifact. See
  /// [createsDriveStateSnapshot].
  final bool offersDriveState;

  const PromptToSnapshotDialog({
    super.key,
    required this.drive,
    required this.promptToSnapshotBloc,
    required this.offersDriveState,
  });

  @override
  PromptToSnapshotDialogState createState() => PromptToSnapshotDialogState();
}

class PromptToSnapshotDialogState extends State<PromptToSnapshotDialog> {
  bool _dontAskAgain = false;

  @override
  Widget build(BuildContext context) {
    // Where publishing is on, the snapshot the nudge offers is a drive state
    // artifact (D14), with the same gate as every "Create snapshot" item -
    // see [createsDriveStateSnapshot]. Hardcoded English, matching
    // `drive_state_creation_modal.dart`, until the feature's strings move into
    // the `.arb` files in one pass.
    final offersDriveState = widget.offersDriveState;
    final localizations = appLocalizationsOf(context);

    final String title;
    final String body;
    if (offersDriveState) {
      title = _dontAskAgain
          ? 'You won\'t be asked again'
          : 'Make this drive load faster';
      body = _dontAskAgain
          ? 'You can create a snapshot at any time from the drive\'s menu.'
          : 'This drive takes a while to sync because its history is read '
              'one change at a time. A snapshot saves the whole drive as one '
              'file on Arweave, so it loads much faster wherever you sign in. '
              'You see the size and the cost before anything is uploaded.';
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
              promptToCreateSnapshot(context, widget.drive);
            },
            title: localizations.createSnapshot,
          ),
      ],
    );
  }
}

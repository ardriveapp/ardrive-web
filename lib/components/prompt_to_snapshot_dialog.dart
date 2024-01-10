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
  required PromptToSnapshotBloc bloc,
}) async {
  return showArDriveDialog(
    context,
    content: PromptToSnapshotDialog(
      bloc: bloc,
      drive: drive,
    ),
  );
}

class PromptToSnapshotDialog extends StatefulWidget {
  final PromptToSnapshotBloc bloc;
  final Drive drive;

  const PromptToSnapshotDialog({
    super.key,
    required this.drive,
    required this.bloc,
  });

  @override
  PromptToSnapshotDialogState createState() => PromptToSnapshotDialogState();
}

class PromptToSnapshotDialogState extends State<PromptToSnapshotDialog> {
  bool _dontAskAgain = false;

  @override
  void initState() {
    super.initState();
    // widget.bloc.add(SelectedDrive(driveId: widget.drive.id));
  }

  @override
  Widget build(BuildContext context) {
    return ArDriveStandardModal(
      hasCloseButton: true,
      title: _dontAskAgain
          ? appLocalizationsOf(context).weWontRemindYou
          : appLocalizationsOf(context).snapshotRecommended,
      content: SizedBox(
        width: kMediumDialogWidth,
        child: Text(
          _dontAskAgain
              ? appLocalizationsOf(context).snapshotRecommendedDontAskAgain
              : appLocalizationsOf(context).snapshotRecommendedBody,
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
                widget.bloc.add(const DismissDontAskAgain(dontAskAgain: true));
              });
            }
          },
          title: _dontAskAgain
              ? appLocalizationsOf(context).okEmphasized
              : appLocalizationsOf(context).dontAskMeAgain,
        ),
        if (!_dontAskAgain)
          ModalAction(
            action: () {
              Navigator.of(context).pop();
              promptToCreateSnapshot(context, widget.drive);
            },
            title: appLocalizationsOf(context).createSnapshot,
          ),
      ],
    );
  }
}

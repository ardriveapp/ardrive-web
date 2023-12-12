import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_bloc.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_event.dart';
import 'package:ardrive/components/create_snapshot_dialog.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

Future<void> promptToSnapshot(
  BuildContext context, {
  required Drive drive,
  required PromptToSnapshotBloc bloc,
}) async {
  logger.d('Prompting to snapshot');
  return showArDriveDialog(
    context,
    content: PromptToSnapshotDialog(
      bloc: bloc,
      drive: drive,
    ),
  );
}

class PromptToSnapshotDialog extends StatelessWidget {
  final PromptToSnapshotBloc bloc;
  final Drive drive;

  const PromptToSnapshotDialog({
    super.key,
    required this.drive,
    required this.bloc,
  });

  @override
  Widget build(BuildContext context) {
    return ArDriveStandardModal(
      hasCloseButton: true,
      title: appLocalizationsOf(context).snapshotRecommended,
      content: SizedBox(
        width: kMediumDialogWidth,
        child: Text(
          appLocalizationsOf(context).snapshotRecommendedBody,
          style: ArDriveTypography.body.buttonNormalRegular(),
        ),
      ),
      actions: [
        ModalAction(
          action: () {
            Navigator.of(context).pop();
            // TODO: are you sure?
            bloc.add(const DismissDontAskAgain());
          },
          title: appLocalizationsOf(context).dontAskMeAgain,
        ),
        ModalAction(
          action: () {
            Navigator.of(context).pop();
            promptToCreateSnapshot(context, drive);
          },
          title: appLocalizationsOf(context).createSnapshot,
        ),
      ],
    );
  }
}

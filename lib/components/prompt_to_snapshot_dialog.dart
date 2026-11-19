import 'dart:async';

import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_bloc.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_event.dart';
import 'package:ardrive/components/create_snapshot_dialog.dart';
import 'package:ardrive/models/database/database.dart';
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

  /// Create snapshot was pressed and is looking up which dialog to open.
  bool _opening = false;

  /// Closes the suggestion. With "Don't ask again" ticked that is also said
  /// to the bloc, in the same step: it used to swap the dialog for a second
  /// screen to confirm a preference.
  void _notNow() {
    if (_dontAskAgain) {
      widget.promptToSnapshotBloc
          .add(const DismissDontAskAgain(dontAskAgain: true));
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Where publishing is on, the snapshot the nudge offers is a drive state
    // artifact (D14), with the same gate as every "Create snapshot" item -
    // see [createsDriveStateSnapshot].
    final localizations = appLocalizationsOf(context);

    final String title = widget.offersDriveState
        ? localizations.snapshotPromptDriveStateTitle
        : localizations.snapshotRecommended;
    final String body = widget.offersDriveState
        ? localizations.snapshotPromptDriveStateBody
        : localizations.snapshotRecommendedBody;
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return ArDriveStandardModalNew(
      title: title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            body,
            style: typography.paragraphNormal(color: colorTokens.textMid),
          ),
          const SizedBox(height: ArDriveSpacing.md),
          ArDriveCheckBox(
            checked: _dontAskAgain,
            title: localizations.dontAskMeAgain,
            titleStyle: typography.paragraphNormal(color: colorTokens.textMid),
            onChange: (value) => setState(() => _dontAskAgain = value),
          ),
        ],
      ),
      actions: [
        ModalAction.close(
          action: _notNow,
          title: localizations.snapshotNotNow,
        ),
        ModalAction(
          // Which dialog opens is looked up before this one closes: after,
          // its context is gone once the close animation ends.
          action: () async {
            if (_opening) return;
            _opening = true;
            final createsDriveState =
                await createsDriveStateSnapshot(context, widget.drive);
            if (!context.mounted) return;
            Navigator.of(context).pop();
            unawaited(promptToCreateSnapshot(
              context,
              widget.drive,
              createsDriveState: createsDriveState,
            ));
          },
          title: localizations.createSnapshot,
        ),
      ],
    );
  }
}

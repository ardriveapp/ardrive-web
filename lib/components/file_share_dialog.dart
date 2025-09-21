import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/copy_button.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/feedback_survey/feedback_survey_cubit.dart';

Future<void> promptToShareFile({
  required BuildContext context,
  required String driveId,
  required String fileId,
}) =>
    showArDriveDialog(
      context,
      content: BlocProvider<FileShareCubit>(
        create: (_) => FileShareCubit(
          driveId: driveId,
          fileId: fileId,
          profileCubit: context.read<ProfileCubit>(),
          driveDao: context.read<DriveDao>(),
        ),
        child: const FileShareDialog(),
      ),
    ).then((value) => context.read<FeedbackSurveyCubit>().openRemindMe());

/// Depends on a provided [FileShareCubit] for business logic.
class FileShareDialog extends StatefulWidget {
  const FileShareDialog({super.key});

  @override
  FileShareDialogState createState() => FileShareDialogState();
}

class FileShareDialogState extends State<FileShareDialog> {
  final shareLinkController = TextEditingController();

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<FileShareCubit, FileShareState>(
        listener: (context, state) {
          if (state is FileShareLoadSuccess) {
            shareLinkController.text = state.fileShareLink.toString();
          }
        },
        builder: (context, state) => ArDriveStandardModal(
          width: kLargeDialogWidth,
          title: appLocalizationsOf(context).shareFileWithOthers,
          description: state is FileShareLoadSuccess ? state.fileName : null,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state is FileShareLoadInProgress)
                const Center(child: CircularProgressIndicator())
              else if (state is FileShareLoadedFailedFile)
                Text(appLocalizationsOf(context).shareFailedFile)
              else if (state is FileShareLoadSuccess) ...{
                if (state.isPending)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        ArDriveIcons.triangle(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeWarningEmphasis,
                        ),
                        const SizedBox(
                          width: 8,
                        ),
                        Flexible(
                          child: Text(
                            'Warning: This file is currently pending and may not be immediately accessible.',
                            style: ArDriveTypography.body.buttonNormalBold(
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeWarningEmphasis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: ArDriveTextField(
                        controller: shareLinkController,
                        isEnabled: false,
                      ),
                    ),
                    const SizedBox(width: 16),
                    CopyButton(
                      positionX: 4,
                      positionY: 40,
                      copyMessageColor: ArDriveTheme.of(context)
                          .themeData
                          .tableTheme
                          .selectedItemColor,
                      showCopyText: true,
                      text: () {
                        // Select the entire link to give the user some feedback on their action.
                        shareLinkController.selection = TextSelection(
                          baseOffset: 0,
                          extentOffset: shareLinkController.text.length,
                        );

                        return shareLinkController.text;
                      }(),
                      child: Text(
                        appLocalizationsOf(context).copyLink,
                        style: ArDriveTypography.body
                            .buttonLargeRegular(
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeFgDefault,
                            )
                            .copyWith(
                              decoration: TextDecoration.underline,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  appLocalizationsOf(context).anyoneCanAccessThisFile,
                  style: ArDriveTypography.body.buttonNormalBold(),
                ),
              }
            ],
          ),
          actions: [
            if (state is FileShareLoadSuccess)
              ModalAction(
                action: () {
                  Navigator.pop(context);
                  context.read<FeedbackSurveyCubit>().openRemindMe();
                },
                title: appLocalizationsOf(context).doneEmphasized,
              ),
            if (state is FileShareLoadedFailedFile ||
                state is FileShareLoadedPendingFile)
              ModalAction(
                action: () => Navigator.pop(context),
                title: appLocalizationsOf(context).ok,
              )
          ],
        ),
      );
}

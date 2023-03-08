import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/feedback_survey/feedback_survey_cubit.dart';

Future<void> promptToShareFile({
  required BuildContext context,
  required String driveId,
  required String fileId,
}) =>
    showAnimatedDialog(
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
    );

/// Depends on a provided [FileShareCubit] for business logic.
class FileShareDialog extends StatefulWidget {
  const FileShareDialog({Key? key}) : super(key: key);

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

          // TODO: Re-enable this when we have a better way to handle the back button.
          // onWillPopCallback: () {
          //   context.read<FeedbackSurveyCubit>().openRemindMe();
          // },
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
              else if (state is FileShareLoadedPendingFile)
                Text(appLocalizationsOf(context).sharePendingFile)
              else if (state is FileShareLoadSuccess) ...{
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
                    ArDriveButton(
                        style: ArDriveButtonStyle.tertiary,
                        text: appLocalizationsOf(context).copyLink,
                        onPressed: () {
                          // Select the entire link to give the user some feedback on their action.
                          shareLinkController.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: shareLinkController.text.length,
                          );

                          Clipboard.setData(
                              ClipboardData(text: shareLinkController.text));
                        }),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  appLocalizationsOf(context).anyoneCanAccessThisFile,
                  style: Theme.of(context).textTheme.subtitle2,
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

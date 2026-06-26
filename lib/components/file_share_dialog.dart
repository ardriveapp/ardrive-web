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
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return BlocConsumer<FileShareCubit, FileShareState>(
      listener: (context, state) {
        if (state is FileShareLoadSuccess) {
          shareLinkController.text = state.fileShareLink.toString();
        }
      },
      builder: (context, state) => ArDriveStandardModalNew(
        width: kLargeDialogWidth,
        title: appLocalizationsOf(context).shareFileWithOthers,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state is FileShareLoadSuccess)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  state.fileName,
                  style: typography.paragraphNormal(
                    fontWeight: ArFontWeight.semiBold,
                    color: colorTokens.textHigh,
                  ),
                ),
              ),
            if (state is FileShareLoadInProgress)
              const Center(child: CircularProgressIndicator())
            else if (state is FileShareLoadedFailedFile)
              Text(
                appLocalizationsOf(context).shareFailedFile,
                style: typography.paragraphNormal(
                  color: colorTokens.textMid,
                ),
              )
            else if (state is FileShareLoadSuccess) ...{
              if (state.isPending)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colorTokens.containerL1,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      ArDriveIcons.triangle(
                        size: 16,
                        color: colorTokens.strokeRed,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Warning: This file is currently pending and may not be immediately accessible.',
                          style: typography.paragraphSmall(
                            fontWeight: ArFontWeight.semiBold,
                            color: colorTokens.strokeRed,
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
                    child: ArDriveTextFieldNew(
                      controller: shareLinkController,
                      isEnabled: false,
                    ),
                  ),
                  const SizedBox(width: 16),
                  CopyButton(
                    positionX: 4,
                    positionY: 40,
                    copyMessageColor: colorTokens.containerRed,
                    showCopyText: true,
                    text: () {
                      shareLinkController.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: shareLinkController.text.length,
                      );
                      return shareLinkController.text;
                    }(),
                    child: Text(
                      appLocalizationsOf(context).copyLink,
                      style: typography
                          .paragraphNormal(
                            fontWeight: ArFontWeight.semiBold,
                            color: colorTokens.textMid,
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
                style: typography.paragraphSmall(
                  color: colorTokens.textLow,
                ),
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
}

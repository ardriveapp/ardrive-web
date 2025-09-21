import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/feedback_survey/feedback_survey_cubit.dart';
import 'package:ardrive/components/copy_button.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> promptToShareDrive({
  required BuildContext context,
  required Drive drive,
}) =>
    showArDriveDialog(
      context,
      content: BlocProvider(
        create: (_) => DriveShareCubit(
          drive: drive,
          driveDao: context.read<DriveDao>(),
          profileCubit: context.read<ProfileCubit>(),
        ),
        child: const DriveShareDialog(),
      ),
    ).then(
      (value) => context.read<FeedbackSurveyCubit>().openRemindMe(),
    );

/// Depends on a provided [DriveShareCubit] for business logic.
class DriveShareDialog extends StatefulWidget {
  const DriveShareDialog({super.key});

  @override
  DriveShareDialogState createState() => DriveShareDialogState();
}

class DriveShareDialogState extends State<DriveShareDialog> {
  final shareLinkController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<DriveShareCubit, DriveShareState>(
        builder: (context, state) {
          final typography = ArDriveTypographyNew.of(context);

          return ArDriveStandardModalNew(
            width: kLargeDialogWidth,
            title: appLocalizationsOf(context).shareDriveWithOthers,
            description:
                state is DriveShareLoadSuccess ? state.drive.name : null,
            content: SizedBox(
              width: kLargeDialogWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (state is DriveShareLoadInProgress)
                    const Center(child: CircularProgressIndicator())
                  else if (state is DriveShareLoadSuccess) ...{
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                            decoration: BoxDecoration(
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colorTokens
                                  .inputDisabled,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colorTokens
                                    .strokeMid,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    state.driveShareLink.toString(),
                                    style: typography.paragraphNormal(
                                      color: ArDriveTheme.of(context)
                                          .themeData
                                          .colorTokens
                                          .textXLow,
                                      fontWeight: ArFontWeight.semiBold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                CopyButton(
                                  text: state.driveShareLink.toString(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      state.drive.isPublic
                          ? appLocalizationsOf(context)
                              .anyoneCanAccessThisDrivePublic
                          : appLocalizationsOf(context)
                              .anyoneCanAccessThisDrivePrivate,
                      style: typography.paragraphLarge(),
                    ),
                  } else if (state is DriveShareLoadFail)
                    Text(state.message)
                ],
              ),
            ),
            actions: [
              if (state is DriveShareLoadSuccess)
                ModalAction(
                  action: () {
                    Navigator.pop(context);
                    context.read<FeedbackSurveyCubit>().openRemindMe();
                  },
                  title: appLocalizationsOf(context).doneEmphasized,
                )
            ],
          );
        },
      );
}

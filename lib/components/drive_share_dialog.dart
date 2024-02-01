import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/feedback_survey/feedback_survey_cubit.dart';
import 'package:ardrive/components/details_panel.dart';
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
  const DriveShareDialog({Key? key}) : super(key: key);

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
        builder: (context, state) => ArDriveStandardModal(
          width: kLargeDialogWidth,
          title: appLocalizationsOf(context).shareDriveWithOthers,
          description: state is DriveShareLoadSuccess ? state.drive.name : null,
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
                      Expanded(
                        child: ArDriveTextField(
                          initialValue: state.driveShareLink.toString(),
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
                        text: state.driveShareLink.toString(),
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
                    state.drive.isPublic
                        ? appLocalizationsOf(context)
                            .anyoneCanAccessThisDrivePublic
                        : appLocalizationsOf(context)
                            .anyoneCanAccessThisDrivePrivate,
                    style: ArDriveTypography.body.buttonLargeRegular(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeFgDefault,
                    ),
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
        ),
      );
}

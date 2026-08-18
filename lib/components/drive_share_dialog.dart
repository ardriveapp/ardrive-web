import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/copyable_share_artifact.dart';
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
      BlocConsumer<DriveShareCubit, DriveShareState>(
        listener: (context, state) {
          if (state is DriveShareLoadSuccess) {
            shareLinkController.text = state.driveShareLink.toString();
          }
        },
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
                    CopyableShareArtifact(
                      label: appLocalizationsOf(context).shareDriveWithOthers,
                      controller: shareLinkController,
                      text: state.driveShareLink.toString(),
                      copyLabel: appLocalizationsOf(context).copyLink,
                      revealLabel:
                          appLocalizationsOf(context).shareDriveRevealLink,
                      // A private drive's link carries the drive key, which
                      // decrypts every file and folder name in the drive and
                      // cannot be rotated. A public drive's link is not a
                      // secret and is left legible.
                      isSecret: state.drive.isPrivate,
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
                    Text(
                      appLocalizationsOf(context).shareDriveFailure,
                      style: typography.paragraphNormal(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colorTokens
                            .textMid,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              if (state is DriveShareLoadFail) ...[
                ModalAction(
                  action: () => Navigator.pop(context),
                  title: appLocalizationsOf(context).cancel,
                ),
                ModalAction(
                  action: () =>
                      context.read<DriveShareCubit>().loadDriveShareDetails(),
                  title: appLocalizationsOf(context).tryAgain,
                ),
              ],
              if (state is DriveShareLoadSuccess)
                ModalAction(
                  action: () => Navigator.pop(context),
                  title: appLocalizationsOf(context).doneEmphasized,
                )
            ],
          );
        },
      );
}

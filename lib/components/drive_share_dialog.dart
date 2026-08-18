import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/copyable_share_artifact.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Shares [drive], or - when [folderId] is given - one folder inside it.
Future<void> promptToShareDrive({
  required BuildContext context,
  required Drive drive,
  String? folderId,
}) =>
    showArDriveDialog(
      context,
      content: BlocProvider(
        create: (_) => DriveShareCubit(
          drive: drive,
          folderId: folderId,
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
  final driveKeyController = TextEditingController();

  @override
  void dispose() {
    shareLinkController.dispose();
    driveKeyController.dispose();
    super.dispose();
  }

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
            driveKeyController.text = state.driveKeyBase64 ?? '';
          }
        },
        builder: (context, state) {
          final typography = ArDriveTypographyNew.of(context);

          return ArDriveStandardModalNew(
            width: kLargeDialogWidth,
            title: state is DriveShareLoadSuccess && state.isFolder
                ? appLocalizationsOf(context).shareFolderWithOthers
                : appLocalizationsOf(context).shareDriveWithOthers,
            description:
                state is DriveShareLoadSuccess ? state.drive.name : null,
            scrollableContent: true,
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
                      label: appLocalizationsOf(context).shareFileLinkLabel,
                      controller: shareLinkController,
                      text: state.driveShareLink.toString(),
                      copyLabel: appLocalizationsOf(context).copyLink,
                      revealLabel:
                          appLocalizationsOf(context).shareDriveRevealLink,
                      // Only a link the sharer chose to embed the key in holds
                      // a secret. A keyless link - the default - is not worth
                      // hiding, and hiding it would suggest it is dangerous to
                      // share, which is the opposite of the point.
                      isSecret: state.keyIsInLink,
                    ),
                    if (state.hasSeparateKeyArtifact) ...{
                      const SizedBox(height: 16),
                      CopyableShareArtifact(
                        label: appLocalizationsOf(context)
                            .shareDriveAccessKeyLabel,
                        controller: driveKeyController,
                        text: state.driveKeyBase64!,
                        copyLabel: appLocalizationsOf(context).copyAccessKey,
                        revealLabel:
                            appLocalizationsOf(context).shareFileRevealKey,
                        isSecret: true,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          appLocalizationsOf(context)
                              .shareDriveSendKeySeparately,
                          style: typography.paragraphSmall(
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colorTokens
                                .textLow,
                          ),
                        ),
                      ),
                    },
                    if (state.drive.isPrivate) ...{
                      const SizedBox(height: 16),
                      ArDriveCheckBox(
                        // The checkbox only reads `checked` when it is first
                        // built, so the key forces a fresh one whenever the
                        // cubit's answer changes.
                        key: ValueKey(state.keyIsInLink),
                        checked: state.keyIsInLink,
                        title: appLocalizationsOf(context)
                            .shareDriveIncludeKeyInLink,
                        titleStyle: typography.paragraphSmall(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colorTokens
                              .textMid,
                        ),
                        onChange: (value) =>
                            context.read<DriveShareCubit>().setKeyIsInLink(
                                  value,
                                ),
                      ),
                      if (state.keyIsInLink)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            appLocalizationsOf(context)
                                .shareDriveKeyInLinkWarning,
                            style: typography.paragraphSmall(
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colorTokens
                                  .strokeRed,
                            ),
                          ),
                        ),
                    },
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

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
///
/// [folderName] is what the dialog shows the sharer they are sharing. Without
/// it a folder share is described by its *drive's* name, which is the wrong
/// thing to confirm before copying a link.
Future<void> promptToShareDrive({
  required BuildContext context,
  required Drive drive,
  String? folderId,
  String? folderName,
}) =>
    showArDriveDialog(
      context,
      content: BlocProvider(
        create: (_) => DriveShareCubit(
          drive: drive,
          folderId: folderId,
          folderName: folderName,
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
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<DriveShareCubit, DriveShareState>(
        builder: (context, state) {
          final typography = ArDriveTypographyNew.of(context);

          return ArDriveStandardModalNew(
            width: kLargeDialogWidth,
            title: state is DriveShareLoadSuccess && state.isFolder
                ? appLocalizationsOf(context).shareFolderWithOthers
                : appLocalizationsOf(context).shareDriveWithOthers,
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
                    // What is being shared, confirmed before the sharer copies
                    // anything. Not the modal's `description`, which it only
                    // renders when there is no `content` - so this dialog never
                    // showed one.
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        state.folderName ?? state.drive.name,
                        style: typography.paragraphNormal(
                          fontWeight: ArFontWeight.semiBold,
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colorTokens
                              .textHigh,
                        ),
                      ),
                    ),
                    CopyableShareArtifact(
                      label: appLocalizationsOf(context).shareFileLinkLabel,
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
                      // A keyless private link does *not* grant access on its
                      // own, so it must not be described as though it does -
                      // that copy predates the key ever being optional.
                      state.drive.isPublic
                          ? appLocalizationsOf(context)
                              .anyoneCanAccessThisDrivePublic
                          : state.keyIsInLink
                              ? appLocalizationsOf(context)
                                  .anyoneCanAccessThisDrivePrivate
                              : appLocalizationsOf(context)
                                  .shareDriveKeylessNotice,
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

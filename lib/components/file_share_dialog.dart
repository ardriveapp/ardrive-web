import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/copyable_share_artifact.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
          arweave: context.read<ArweaveService>(),
        ),
        child: const FileShareDialog(),
      ),
    );

/// Depends on a provided [FileShareCubit] for business logic.
///
/// A private file is shared as *two* artifacts: the link, and the access key
/// that opens it. They are copied separately and meant to travel through
/// different channels - see `docs/FILE_SHARING_REDESIGN_PLAN.md` decision 4.
/// A public file has a single artifact and none of the key affordances.
class FileShareDialog extends StatefulWidget {
  const FileShareDialog({super.key});

  @override
  FileShareDialogState createState() => FileShareDialogState();
}

class FileShareDialogState extends State<FileShareDialog> {

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return BlocBuilder<FileShareCubit, FileShareState>(
      builder: (context, state) => ArDriveStandardModalNew(
        width: kLargeDialogWidth,
        scrollableContent: true,
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
            else if (state is FileShareLoadedPendingFile)
              Text(
                appLocalizationsOf(context).sharePendingFile,
                style: typography.paragraphNormal(
                  color: colorTokens.textMid,
                ),
              )
            // A list spread, not a set: the same `const SizedBox` appears more
            // than once below, and a set literal would silently collapse them
            // into one.
            else if (state is FileShareLoadSuccess) ...[
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
                          // TODO(PE-9103): extract to ARB localization files
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
              CopyableShareArtifact(
                label: appLocalizationsOf(context).shareFileLinkLabel,
                text: state.fileShareLink.toString(),
                copyLabel: appLocalizationsOf(context).copyLink,
                revealLabel: appLocalizationsOf(context).shareDriveRevealLink,
                // A link only holds a secret when the sharer chose to embed
                // the key in it. A keyless link is not worth hiding.
                isSecret: state.keyIsInLink,
              ),
              if (state.isLoadingCipherDetails)
                _HelperText(
                  appLocalizationsOf(context).shareFileFinishingLink,
                  color: colorTokens.textLow,
                ),
              if (state.isPublicFile)
                _HelperText(
                  appLocalizationsOf(context).anyoneCanAccessThisFile,
                  color: colorTokens.textLow,
                ),
              if (state.hasSeparateKeyArtifact) ...[
                const SizedBox(height: 16),
                CopyableShareArtifact(
                  label: appLocalizationsOf(context).shareFileAccessKeyLabel,
                  text: state.fileKeyBase64!,
                  copyLabel: appLocalizationsOf(context).copyAccessKey,
                  revealLabel: appLocalizationsOf(context).shareFileRevealKey,
                  isSecret: true,
                ),
                _HelperText(
                  appLocalizationsOf(context).shareFileSendKeySeparately,
                  color: colorTokens.textLow,
                ),
              ],
              if (!state.isPublicFile) ...[
                const SizedBox(height: 16),
                ArDriveCheckBox(
                  // [ArDriveCheckBox] only reads `checked` when it is first
                  // built, so the key forces a fresh one whenever the cubit's
                  // answer changes.
                  key: ValueKey(state.keyIsInLink),
                  checked: state.keyIsInLink,
                  title: appLocalizationsOf(context).shareFileIncludeKeyInLink,
                  titleStyle: typography.paragraphSmall(
                    color: colorTokens.textMid,
                  ),
                  onChange: (value) =>
                      context.read<FileShareCubit>().setKeyIsInLink(value),
                ),
                if (state.keyIsInLink)
                  _HelperText(
                    appLocalizationsOf(context).shareFileKeyInLinkWarning,
                    color: colorTokens.strokeRed,
                  ),
                const SizedBox(height: 16),
                ArDriveToggleSwitch(
                  text: appLocalizationsOf(context).shareFileHideDetails,
                  textStyle: typography.paragraphSmall(
                    color: colorTokens.textMid,
                  ),
                  value: state.detailsAreHidden,
                  onChanged: (value) => context
                      .read<FileShareCubit>()
                      .setDetailsAreHidden(value),
                ),
                _HelperText(
                  appLocalizationsOf(context).shareFileHideDetailsDescription,
                  color: colorTokens.textLow,
                ),
              ],
              const SizedBox(height: 16),
              ArDriveToggleSwitch(
                text: appLocalizationsOf(context).shareFilePinToThisVersion,
                textStyle: typography.paragraphSmall(
                  color: colorTokens.textMid,
                ),
                value: state.isPinned,
                onChanged: (value) => context
                    .read<FileShareCubit>()
                    .setPinnedToCurrentVersion(value),
              ),
              _HelperText(
                appLocalizationsOf(context)
                    .shareFilePinToThisVersionDescription,
                color: colorTokens.textLow,
              ),
            ],
          ],
        ),
        actions: [
          if (state is FileShareLoadSuccess)
            ModalAction(
              action: () => Navigator.pop(context),
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

class _HelperText extends StatelessWidget {
  const _HelperText(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          text,
          style: ArDriveTypographyNew.of(context).paragraphSmall(color: color),
        ),
      );
}

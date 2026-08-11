import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/copy_button.dart';
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
  final shareLinkController = TextEditingController();
  final fileKeyController = TextEditingController();

  @override
  void dispose() {
    shareLinkController.dispose();
    fileKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return BlocConsumer<FileShareCubit, FileShareState>(
      listener: (context, state) {
        if (state is FileShareLoadSuccess) {
          shareLinkController.text = state.fileShareLink.toString();
          fileKeyController.text = state.fileKeyBase64 ?? '';
        }
      },
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
              _CopyableArtifact(
                label: appLocalizationsOf(context).shareFileLinkLabel,
                controller: shareLinkController,
                text: state.fileShareLink.toString(),
                copyLabel: appLocalizationsOf(context).copyLink,
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
                _CopyableArtifact(
                  label: appLocalizationsOf(context).shareFileAccessKeyLabel,
                  controller: fileKeyController,
                  text: state.fileKeyBase64!,
                  copyLabel: appLocalizationsOf(context).copyAccessKey,
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

/// A read-only field holding one of the artifacts of the handover, with its
/// own copy affordance - the link and the key are copied one at a time, on
/// purpose.
class _CopyableArtifact extends StatelessWidget {
  const _CopyableArtifact({
    required this.label,
    required this.controller,
    required this.text,
    required this.copyLabel,
  });

  final String label;
  final TextEditingController controller;

  /// What the copy button puts on the clipboard. Taken from the state rather
  /// than from [controller], which is only how the value is displayed.
  final String text;

  final String copyLabel;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: ArDriveTextFieldNew(
            label: label,
            controller: controller,
            isEnabled: false,
          ),
        ),
        const SizedBox(width: 16),
        CopyButton(
          positionX: 4,
          positionY: 40,
          copyMessageColor: colorTokens.containerRed,
          showCopyText: true,
          text: text,
          child: Text(
            copyLabel,
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

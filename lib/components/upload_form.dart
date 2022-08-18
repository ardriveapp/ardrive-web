import 'dart:html';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/feedback_survey/feedback_survey_cubit.dart';
import 'package:ardrive/blocs/upload/enums/conflicting_files_actions.dart';
import 'package:ardrive/blocs/upload/models/web_file.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/upload_plan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components.dart';

Future<void> promptToUpload(
  BuildContext context, {
  required String driveId,
  required String folderId,
  required bool isFolderUpload,
}) async {
  final uploadInput = FileUploadInputElement();

  if (isFolderUpload) {
    uploadInput.setAttribute('webkitdirectory', true);
  } else {
    uploadInput.setAttribute('webkitEntries', true);
    uploadInput.setAttribute('multiple', true);
  }

  uploadInput.click();
// Create and click upload input element

  uploadInput.onChange.listen((e) async {
    // read file content as dataURL
    final files = uploadInput.files;
    if (files == null) {
      return;
    }
    final selectedFiles = files.map((file) {
      return WebFile(file, folderId);
    }).toList();
    if (selectedFiles.isEmpty) {
      return;
    }
    await showCongestionDependentModalDialog(
      context,
      () => showDialog(
        context: context,
        builder: (_) => BlocProvider<UploadCubit>(
          create: (context) => UploadCubit(
            uploadPlanUtils: UploadPlanUtils(
              arweave: context.read<ArweaveService>(),
              driveDao: context.read<DriveDao>(),
            ),
            driveId: driveId,
            folderId: folderId,
            files: selectedFiles,
            profileCubit: context.read<ProfileCubit>(),
            arweave: context.read<ArweaveService>(),
            pst: context.read<PstService>(),
            driveDao: context.read<DriveDao>(),
            uploadFolders: isFolderUpload,
          )..startUploadPreparation(),
          child: const UploadForm(),
        ),
        barrierDismissible: false,
      ),
    );
  });
}

class UploadForm extends StatelessWidget {
  const UploadForm({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => BlocConsumer<UploadCubit, UploadState>(
        listener: (context, state) async {
          if (state is UploadComplete || state is UploadWalletMismatch) {
            Navigator.pop(context);
            await context.read<FeedbackSurveyCubit>().openRemindMe();
          } else if (state is UploadPreparationInitialized) {
            context.read<UploadCubit>().checkFilesAboveLimit();
          }
          if (state is UploadWalletMismatch) {
            Navigator.pop(context);
            await context.read<ProfileCubit>().logoutProfile();
          }
        },
        builder: (context, state) {
          if (state is UploadFolderNameConflict) {
            return AppDialog(
              title: appLocalizationsOf(context).duplicateFolders(
                state.conflictingFileNames.length,
              ),
              content: SizedBox(
                width: kMediumDialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appLocalizationsOf(context)
                          .foldersWithTheSameNameAlreadyExists(
                        state.conflictingFileNames.length,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(appLocalizationsOf(context).conflictingFiles),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: SingleChildScrollView(
                        child: Text(
                          state.conflictingFileNames.join(', \n'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                if (!state.areAllFilesConflicting)
                  TextButton(
                    style: ButtonStyle(
                        fixedSize: MaterialStateProperty.all(
                            const Size.fromWidth(140))),
                    onPressed: () =>
                        context.read<UploadCubit>().checkConflictingFiles(),
                    child: Text(appLocalizationsOf(context).skipEmphasized),
                  ),
                TextButton(
                  style: ButtonStyle(
                      fixedSize:
                          MaterialStateProperty.all(const Size.fromWidth(140))),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(appLocalizationsOf(context).cancelEmphasized),
                ),
              ],
            );
          } else if (state is UploadFileConflict) {
            return AppDialog(
                title: appLocalizationsOf(context)
                    .duplicateFiles(state.conflictingFileNames.length),
                content: SizedBox(
                  width: kMediumDialogWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appLocalizationsOf(context)
                            .filesWithTheSameNameAlreadyExists(
                          state.conflictingFileNames.length,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(appLocalizationsOf(context).conflictingFiles),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 320),
                        child: SingleChildScrollView(
                          child: Text(
                            state.conflictingFileNames.join(', \n'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: <Widget>[
                  if (!state.areAllFilesConflicting)
                    TextButton(
                      onPressed: () => context
                          .read<UploadCubit>()
                          .prepareUploadPlanAndCostEstimates(
                              uploadAction: UploadActions.skip),
                      child: Text(appLocalizationsOf(context).skipEmphasized),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(appLocalizationsOf(context).cancelEmphasized),
                  ),
                  TextButton(
                    onPressed: () => context
                        .read<UploadCubit>()
                        .prepareUploadPlanAndCostEstimates(
                            uploadAction: UploadActions.replace),
                    child: Text(appLocalizationsOf(context).replaceEmphasized),
                  ),
                ]);
          } else if (state is UploadFileTooLarge) {
            return AppDialog(
              title: appLocalizationsOf(context)
                  .filesTooLarge(state.tooLargeFileNames.length),
              content: SizedBox(
                width: kMediumDialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.isPrivate
                          ? appLocalizationsOf(context)
                              .filesTooLargeExplanationPrivate
                          : appLocalizationsOf(context)
                              .filesTooLargeExplanationPublic,
                    ),
                    const SizedBox(height: 16),
                    Text(appLocalizationsOf(context).tooLargeForUpload),
                    const SizedBox(height: 8),
                    Text(state.tooLargeFileNames.join(', ')),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(appLocalizationsOf(context).cancelEmphasized),
                ),
                if (state.hasFilesToUpload)
                  TextButton(
                    onPressed: () {
                      context.read<UploadCubit>().removeBigFiles();
                      context.read<UploadCubit>().checkConflicts();
                    },
                    child: Text(appLocalizationsOf(context).skipEmphasized),
                  ),
              ],
            );
          } else if (state is UploadPreparationInProgress ||
              state is UploadPreparationInitialized) {
            return AppDialog(
              title: appLocalizationsOf(context).preparingUpload,
              content: SizedBox(
                width: kMediumDialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    if (state is UploadPreparationInProgress &&
                        state.isArConnect)
                      Text(appLocalizationsOf(context).arConnectRemainOnThisTab)
                    else
                      Text(appLocalizationsOf(context).thisMayTakeAWhile)
                  ],
                ),
              ),
            );
          } else if (state is UploadReady) {
            final numberOfFilesInBundles =
                state.uploadPlan.bundleUploadHandles.isNotEmpty
                    ? state.uploadPlan.bundleUploadHandles
                        .map((e) => e.numberOfFiles)
                        .reduce((value, element) => value += element)
                    : 0;
            final numberOfV2Files = state.uploadPlan.fileV2UploadHandles.length;
            return AppDialog(
              title: appLocalizationsOf(context)
                  .uploadNFiles(numberOfFilesInBundles + numberOfV2Files),
              content: SizedBox(
                width: kMediumDialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 256),
                      child: Scrollbar(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final file in state
                                .uploadPlan.fileV2UploadHandles.values) ...{
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(file.entity.name!),
                                subtitle: Text(filesize(file.size)),
                              ),
                            },
                            for (final bundle
                                in state.uploadPlan.bundleUploadHandles) ...{
                              for (final fileEntity in bundle.fileEntities) ...{
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(fileEntity.name!),
                                  subtitle: Text(filesize(fileEntity.size)),
                                ),
                              },
                            },
                          ],
                        ),
                      ),
                    ),
                    const Divider(),
                    const SizedBox(height: 16),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: appLocalizationsOf(context)
                                .cost(state.costEstimate.arUploadCost),
                          ),
                          if (state.costEstimate.usdUploadCost != null)
                            TextSpan(
                                text: state.costEstimate.usdUploadCost! >= 0.01
                                    ? ' (~${state.costEstimate.usdUploadCost!.toStringAsFixed(2)} USD)'
                                    : ' (< 0.01 USD)'),
                        ],
                        style: Theme.of(context).textTheme.bodyText1,
                      ),
                    ),
                    if (state.uploadIsPublic) ...{
                      const SizedBox(height: 8),
                      Text(
                        appLocalizationsOf(context).filesWillBeUploadedPublicly(
                            numberOfFilesInBundles + numberOfV2Files),
                      ),
                    },
                    if (!state.sufficientArBalance) ...{
                      const SizedBox(height: 8),
                      Text(
                        appLocalizationsOf(context).insufficientARForUpload,
                        style: DefaultTextStyle.of(context)
                            .style
                            .copyWith(color: Theme.of(context).errorColor),
                      ),
                    },
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(appLocalizationsOf(context).cancelEmphasized),
                ),
                ElevatedButton(
                  onPressed: state.sufficientArBalance
                      ? () => context.read<UploadCubit>().startUpload(
                            uploadPlan: state.uploadPlan,
                            costEstimate: state.costEstimate,
                          )
                      : null,
                  child: Text(appLocalizationsOf(context).uploadEmphasized),
                ),
              ],
            );
          } else if (state is UploadSigningInProgress) {
            return AppDialog(
              title: state.uploadPlan.bundleUploadHandles.isNotEmpty
                  ? appLocalizationsOf(context).bundlingAndSigningUpload
                  : appLocalizationsOf(context).signingUpload,
              content: SizedBox(
                width: kMediumDialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    if (state.isArConnect)
                      Text(appLocalizationsOf(context).arConnectRemainOnThisTab)
                    else
                      Text(appLocalizationsOf(context).thisMayTakeAWhile)
                  ],
                ),
              ),
            );
          } else if (state is UploadInProgress) {
            final numberOfFilesInBundles =
                state.uploadPlan.bundleUploadHandles.isNotEmpty
                    ? state.uploadPlan.bundleUploadHandles
                        .map((e) => e.numberOfFiles)
                        .reduce((value, element) => value += element)
                    : 0;
            final numberOfV2Files = state.uploadPlan.fileV2UploadHandles.length;
            return AppDialog(
              dismissable: false,
              title: appLocalizationsOf(context)
                  .uploadingNFiles(numberOfFilesInBundles + numberOfV2Files),
              content: SizedBox(
                width: kMediumDialogWidth,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 256),
                  child: Scrollbar(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final file
                            in state.uploadPlan.fileV2UploadHandles.values) ...{
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(file.entity.name!),
                            subtitle: Text(
                                '${filesize(file.uploadedSize)}/${filesize(file.size)}'),
                            trailing: CircularProgressIndicator(
                                // Show an indeterminate progress indicator if the upload hasn't started yet as
                                // small uploads might never report a progress.
                                value: file.uploadProgress != 0
                                    ? file.uploadProgress
                                    : null),
                          ),
                        },
                        for (final bundle
                            in state.uploadPlan.bundleUploadHandles) ...{
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (var fileEntity in bundle.fileEntities)
                                  Text(fileEntity.name!)
                              ],
                            ),
                            subtitle: Text(
                                '${filesize(bundle.uploadedSize)}/${filesize(bundle.size)}'),
                            trailing: CircularProgressIndicator(
                                // Show an indeterminate progress indicator if the upload hasn't started yet as
                                // small uploads might never report a progress.
                                value: bundle.uploadProgress != 0
                                    ? bundle.uploadProgress
                                    : null),
                          ),
                        },
                      ],
                    ),
                  ),
                ),
              ),
            );
          } else if (state is UploadFailure) {
            return AppDialog(
              title: appLocalizationsOf(context).uploadFailed,
              content: SizedBox(
                width: kMediumDialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(appLocalizationsOf(context).yourUploadFailed),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(appLocalizationsOf(context).okEmphasized),
                ),
              ],
            );
          }
          return const SizedBox();
        },
      );
}

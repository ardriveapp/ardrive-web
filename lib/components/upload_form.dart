import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:file_selector/file_selector.dart';
import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'components.dart';

Future<void> promptToUploadFile(
  BuildContext context, {
  required String driveId,
  required String folderId,
}) async {
  final selectedFiles = await openFiles();
  if (selectedFiles.isEmpty) {
    return;
  }
  await showCongestionDependentModalDialog(
    context,
    () => showDialog(
      context: context,
      builder: (_) => BlocProvider<UploadCubit>(
        create: (context) => UploadCubit(
          driveId: driveId,
          folderId: folderId,
          files: selectedFiles,
          profileCubit: context.read<ProfileCubit>(),
          arweave: context.read<ArweaveService>(),
          pst: context.read<PstService>(),
          driveDao: context.read<DriveDao>(),
        ),
        child: UploadForm(),
      ),
      barrierDismissible: false,
    ),
  );
}

class UploadForm extends StatelessWidget {
  @override
  Widget build(BuildContext context) => BlocConsumer<UploadCubit, UploadState>(
        listener: (context, state) async {
          if (state is UploadComplete || state is UploadWalletMismatch) {
            Navigator.pop(context);
          }
          if (state is UploadWalletMismatch) {
            Navigator.pop(context);
            await context.read<ProfileCubit>().logoutProfile();
          }
        },
        builder: (context, state) {
          if (state is UploadFileConflict) {
            return AppDialog(
              title: AppLocalizations.of(context)!
                  .conflictingFilesFound(state.conflictingFileNames.length),
              content: SizedBox(
                width: kMediumDialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(state.conflictingFileNames.length == 1
                        ? AppLocalizations.of(context)!
                            .aFileWithSameNameAlreadyExists
                        : AppLocalizations.of(context)!
                            .filesWithTheSameNameAlreadyExists(
                                state.conflictingFileNames.length)),
                    const SizedBox(height: 16),
                    Text(AppLocalizations.of(context)!.conflictingFiles),
                    const SizedBox(height: 8),
                    Text(state.conflictingFileNames.join(', ')),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                      AppLocalizations.of(context)!.cancelUploadEmphasized),
                ),
                ElevatedButton(
                  onPressed: () => context
                      .read<UploadCubit>()
                      .prepareUploadPlanAndCostEstimates(),
                  child: Text(
                      AppLocalizations.of(context)!.continueUploadEmphasized),
                ),
              ],
            );
          } else if (state is UploadFileTooLarge) {
            return AppDialog(
              title: AppLocalizations.of(context)!
                  .filesTooLarge(state.tooLargeFileNames.length),
              content: SizedBox(
                width: kMediumDialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.isPrivate
                          ? AppLocalizations.of(context)!
                              .filesTooLargeExplanationPrivate
                          : AppLocalizations.of(context)!
                              .filesTooLargeExplanationPublic,
                    ),
                    const SizedBox(height: 16),
                    Text(AppLocalizations.of(context)!.tooLargeForUpload),
                    const SizedBox(height: 8),
                    Text(state.tooLargeFileNames.join(', ')),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(AppLocalizations.of(context)!.okUpload),
                ),
              ],
            );
          } else if (state is UploadPreparationInProgress) {
            return AppDialog(
              title: AppLocalizations.of(context)!.preparingUpload,
              content: SizedBox(
                width: kMediumDialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    if (state.isArConnect)
                      Text(AppLocalizations.of(context)!
                          .arConnectremainOnThisTab)
                    else
                      Text(AppLocalizations.of(context)!.thisMayTakeAWhile)
                  ],
                ),
              ),
            );
          } else if (state is UploadPreparationFailure) {
            return AppDialog(
              title: AppLocalizations.of(context)!.failedToPrepareFileUpload,
              content: SizedBox(
                width: kMediumDialogWidth,
                child: Text(
                  AppLocalizations.of(context)!
                      .failedToPrepareFileUploadExplanation,
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                      AppLocalizations.of(context)!.closeUploadFormEmphasized),
                ),
              ],
            );
          } else if (state is UploadReady) {
            final numberOfFilesInBundles =
                state.uploadPlan.bundleUploadHandles.isNotEmpty
                    ? state.uploadPlan.bundleUploadHandles
                        .map((e) => e.numberOfFiles)
                        .reduce((value, element) => value += element)
                    : 0;
            final numberOfV2Files = state.uploadPlan.v2FileUploadHandles.length;
            return AppDialog(
              title: AppLocalizations.of(context)!
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
                                .uploadPlan.v2FileUploadHandles.values) ...{
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
                    Divider(),
                    const SizedBox(height: 16),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: AppLocalizations.of(context)!
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
                      Text(AppLocalizations.of(context)!
                          .filesWillBeUploadedPublicly),
                    },
                    if (!state.sufficientArBalance) ...{
                      const SizedBox(height: 8),
                      Text(
                        AppLocalizations.of(context)!.insufficientARForUpload,
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
                  child: Text(
                      AppLocalizations.of(context)!.cancelUploadEmphasized),
                ),
                ElevatedButton(
                  onPressed: state.sufficientArBalance
                      ? () => context.read<UploadCubit>().startUpload(
                            uploadPlan: state.uploadPlan,
                            costEstimate: state.costEstimate,
                          )
                      : null,
                  child: Text('UPLOAD'),
                ),
              ],
            );
          } else if (state is UploadSigningInProgress) {
            return AppDialog(
              title: state.uploadPlan.bundleUploadHandles.isNotEmpty
                  ? AppLocalizations.of(context)!.bundlingAndSigning
                  : AppLocalizations.of(context)!.signing,
              content: SizedBox(
                width: kMediumDialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    if (state.isArConnect)
                      Text(AppLocalizations.of(context)!
                          .arConnectremainOnThisTab)
                    else
                      Text(AppLocalizations.of(context)!.thisMayTakeAWhile)
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
            final numberOfV2Files = state.uploadPlan.v2FileUploadHandles.length;
            return AppDialog(
              dismissable: false,
              title: AppLocalizations.of(context)!
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
                            in state.uploadPlan.v2FileUploadHandles.values) ...{
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
          }

          return const SizedBox();
        },
      );
}

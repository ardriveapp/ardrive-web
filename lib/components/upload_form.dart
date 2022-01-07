import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:file_selector/file_selector.dart';
import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
              title:
                  '${state.conflictingFileNames.length} conflicting file(s) found',
              content: SizedBox(
                width: kMediumDialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.conflictingFileNames.length == 1
                          ? 'A file with the same name already exists at this location. Do you want to continue and upload this file as a new version?'
                          : '${state.conflictingFileNames.length} files with the same name already exists at this location. Do you want to continue and upload these files as a new version?',
                    ),
                    const SizedBox(height: 16),
                    Text('Conflicting files:'),
                    const SizedBox(height: 8),
                    Text(state.conflictingFileNames.join(', ')),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('CANCEL'),
                ),
                ElevatedButton(
                  onPressed: () => context.read<UploadCubit>().prepareUpload(),
                  child: Text('CONTINUE'),
                ),
              ],
            );
          } else if (state is UploadFileTooLarge) {
            return AppDialog(
              title: '${state.tooLargeFileNames.length} file(s) too large',
              content: SizedBox(
                width: kMediumDialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ArDrive on web currently only supports file uploads smaller than '
                      '${state.isPrivate ? '100 MB for private drives' : '1.25 GB for public drives'}.',
                    ),
                    const SizedBox(height: 16),
                    Text('Too large for upload:'),
                    const SizedBox(height: 8),
                    Text(state.tooLargeFileNames.join(', ')),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('OK'),
                ),
              ],
            );
          } else if (state is UploadPreparationInProgress) {
            return AppDialog(
              title: 'Preparing upload...',
              content: SizedBox(
                width: kMediumDialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    if (state.isArConnect)
                      Text(
                        'CAUTION: Your Web3 wallet is signing your transactions. Please remain on this tab until it has completed.',
                      )
                    else
                      Text('This may take a while...')
                  ],
                ),
              ),
            );
          } else if (state is UploadPreparationFailure) {
            return AppDialog(
              title: 'Failed to prepare file upload',
              content: SizedBox(
                width: kMediumDialogWidth,
                child: Text(
                  'An error occured while preparing your file upload. Please use the desktop app for now instead or try uploading a smaller file.',
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('CLOSE'),
                ),
              ],
            );
          } else if (state is UploadReady) {
            return AppDialog(
              title: 'Upload ${state.files.length} file(s)',
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
                            for (final file in state.files) ...{
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(file.entity.name!),
                                subtitle: Text(filesize(file.size)),
                              ),
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
                          TextSpan(text: 'Cost: ${state.arUploadCost} AR'),
                          if (state.usdUploadCost != null)
                            TextSpan(
                                text: state.usdUploadCost! >= 0.01
                                    ? ' (~${state.usdUploadCost!.toStringAsFixed(2)} USD)'
                                    : ' (< 0.01 USD)'),
                        ],
                        style: Theme.of(context).textTheme.bodyText1,
                      ),
                    ),
                    if (state.uploadIsPublic) ...{
                      const SizedBox(height: 8),
                      Text('These file(s) will be uploaded publicly.'),
                    },
                    if (!state.sufficientArBalance) ...{
                      const SizedBox(height: 8),
                      Text(
                        'Insufficient AR for upload.',
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
                  child: Text('CANCEL'),
                ),
                ElevatedButton(
                  onPressed: state.sufficientArBalance
                      ? () => context.read<UploadCubit>().startUpload()
                      : null,
                  child: Text('UPLOAD'),
                ),
              ],
            );
          } else if (state is UploadBundlingInProgress) {
            return AppDialog(
              title: 'Bundling upload...',
              content: SizedBox(
                width: kMediumDialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    if (state.isArConnect)
                      Text(
                        'CAUTION: Your Web3 wallet is signing your transactions. Please remain on this tab until it has completed.',
                      )
                    else
                      Text('This may take a while...')
                  ],
                ),
              ),
            );
          } else if (state is UploadInProgress) {
            final numberOfFilesInBundles = state.bundles
                .map((e) => e.numberOfFiles)
                .reduce((value, element) => value += element);
            final numberOfV2Files = state.files.length;
            return AppDialog(
              dismissable: false,
              title:
                  'Uploading ${numberOfFilesInBundles + numberOfV2Files} file(s)...',
              content: SizedBox(
                width: kMediumDialogWidth,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 256),
                  child: Scrollbar(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final file in state.files) ...{
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
                        for (final bundle in state.bundles) ...{
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

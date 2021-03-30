import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components.dart';

Future<void> promptToReuploadFile(
  BuildContext context, {
  @required String driveId,
  @required String folderId,
  @required FileWithLatestRevisionTransactions file,
}) async {
  final selectedFiles = [await file_selector.openFile()];
  await showDialog(
    context: context,
    builder: (_) => BlocProvider<RetryUploadCubit>(
      create: (context) => RetryUploadCubit(
        driveId: driveId,
        folderId: folderId,
        fileToUpload: selectedFiles.first,
        uploadedFile: file,
        arweave: context.read<ArweaveService>(),
        pst: context.read<PstService>(),
        profileCubit: context.read<ProfileCubit>(),
        driveDao: context.read<DriveDao>(),
      ),
      child: RetryUploadForm(),
    ),
    barrierDismissible: false,
  );
}

class RetryUploadForm extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      BlocConsumer<RetryUploadCubit, RetryUploadState>(
        listener: (context, state) async {
          if (state is UploadComplete) {
            Navigator.pop(context);
          }
        },
        builder: (context, state) {
          if (state is RetryUploadFileConflict) {
            return AppDialog(
              title: 'Conflicting file(s) found',
              content: SizedBox(
                width: kMediumDialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Incorrect File Selected'),
                    const SizedBox(height: 16),
                    Text('Conflicting files:'),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text('CANCEL'),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                ElevatedButton(
                  child: Text('CONTINUE'),
                  onPressed: () =>
                      context.read<RetryUploadCubit>().prepareUpload(),
                ),
              ],
            );
          } else if (state is RetryUploadFileTooLarge) {
            return AppDialog(
              title: '${state.tooLargeFileNames.length} file(s) too large',
              content: SizedBox(
                width: kMediumDialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        'ArDrive on web currently only supports file uploads smaller than 1.25 GB.'),
                    const SizedBox(height: 16),
                    Text('Too large for upload:'),
                    const SizedBox(height: 8),
                    Text(state.tooLargeFileNames.join(', ')),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text('OK'),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            );
          } else if (state is RetryUploadPreparationInProgress) {
            return AppDialog(
              title: 'Preparing upload...',
              content: SizedBox(
                width: kMediumDialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text('This may take a while...'),
                  ],
                ),
              ),
            );
          } else if (state is RetryUploadPreparationFailure) {
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
                  child: Text('CLOSE'),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            );
          } else if (state is RetryUploadReady) {
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
                                title: Text(file.entity.name),
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
                                text: state.usdUploadCost >= 0.01
                                    ? ' (~${state.usdUploadCost.toStringAsFixed(2)} USD)'
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
                  child: Text('CANCEL'),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                ElevatedButton(
                  child: Text('UPLOAD'),
                  onPressed: state.sufficientArBalance
                      ? () => context.read<RetryUploadCubit>().startUpload()
                      : null,
                ),
              ],
            );
          } else if (state is RetryUploadInProgress) {
            return AppDialog(
              dismissable: false,
              title: 'Uploading ${state.files.length} file(s)...',
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
                            title: Text(file.entity.name),
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

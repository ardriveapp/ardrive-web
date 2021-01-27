import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components.dart';

Future<void> promptToUploadFile(
  BuildContext context, {
  @required String driveId,
  @required String folderId,
  bool allowSelectMultiple = false,
}) async {
  final selectedFiles = allowSelectMultiple
      ? await file_selector.openFiles()
      : [await file_selector.openFile()];

  if (selectedFiles.isEmpty || selectedFiles.first == null) {
    return;
  }

  await showDialog(
    context: context,
    builder: (_) => BlocProvider<UploadCubit>(
      create: (context) => UploadCubit(
        driveId: driveId,
        folderId: folderId,
        files: selectedFiles,
        arweave: context.read<ArweaveService>(),
        pst: context.read<PstService>(),
        profileCubit: context.read<ProfileCubit>(),
        driveDao: context.read<DriveDao>(),
      ),
      child: UploadForm(),
    ),
    barrierDismissible: false,
  );
}

class UploadForm extends StatelessWidget {
  @override
  Widget build(BuildContext context) => BlocConsumer<UploadCubit, UploadState>(
        listener: (context, state) async {
          if (state is UploadComplete) {
            Navigator.pop(context);
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
                  child: Text('CANCEL'),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                ElevatedButton(
                  child: Text('CONTINUE'),
                  onPressed: () => context.read<UploadCubit>().prepareUpload(),
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
                    Text('This may take a while...'),
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
                  child: Text('CLOSE'),
                  onPressed: () => Navigator.of(context).pop(false),
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
                    Text('Cost: ${utils.winstonToAr(state.totalCost)} AR'),
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
                      ? () => context.read<UploadCubit>().startUpload()
                      : null,
                ),
              ],
            );
          } else if (state is UploadInProgress) {
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

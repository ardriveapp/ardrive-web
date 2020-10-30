import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:file_picker_cross/file_picker_cross.dart';
import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components.dart';

Future<void> promptToUpload(
  BuildContext context, {
  @required String driveId,
  @required String folderId,
  @required FilePickerCross file,
}) =>
    showDialog(
      context: context,
      builder: (_) => UploadForm(
        driveId: driveId,
        folderId: folderId,
        file: file,
      ),
      barrierDismissible: false,
    );

class UploadForm extends StatelessWidget {
  final String driveId;
  final String folderId;
  final FilePickerCross file;

  UploadForm(
      {@required this.driveId, @required this.folderId, @required this.file});

  @override
  Widget build(BuildContext context) => BlocProvider<UploadCubit>(
        create: (context) => UploadCubit(
          driveId: driveId,
          folderId: folderId,
          file: file,
          arweave: context.repository<ArweaveService>(),
          profileCubit: context.bloc<ProfileCubit>(),
          driveDao: context.repository<DriveDao>(),
        ),
        child: BlocConsumer<UploadCubit, UploadState>(
          listener: (context, state) async {
            if (state is UploadComplete) {
              Navigator.pop(context);
            }
          },
          builder: (context, state) {
            if (state is UploadFileAlreadyExists) {
              return AppDialog(
                title: 'File with name already exists',
                content: SizedBox(
                  width: kMediumDialogWidth,
                  child: Text(
                    '"${state.existingFileName}" already exists at this location. Do you want to continue and version this file?',
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    child: Text('CANCEL'),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  ElevatedButton(
                    child: Text('UPLOAD AS NEW VERSION'),
                    onPressed: () =>
                        context.bloc<UploadCubit>().prepareUpload(),
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
                      CircularProgressIndicator(),
                      Container(height: 16),
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
            } else if (state is UploadFileReady) {
              return AppDialog(
                title: 'Upload file',
                content: SizedBox(
                  width: kMediumDialogWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(state.fileName),
                        subtitle: Text(filesize(state.uploadSize)),
                      ),
                      Container(height: 16),
                      Text('Cost: ${utils.winstonToAr(state.uploadCost)} AR')
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
                    onPressed: () => context.bloc<UploadCubit>().startUpload(),
                  ),
                ],
              );
            } else if (state is UploadFileInProgress) {
              return AppDialog(
                dismissable: false,
                title: 'Uploading file...',
                content: SizedBox(
                  width: kMediumDialogWidth,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(state.fileName),
                    subtitle: Text(
                        '${filesize(state.uploadedFileSize)}/${filesize(state.fileSize)}'),
                    trailing: CircularProgressIndicator(
                        // Show an indeterminate progress indicator if the upload hasn't started yet as
                        // small uploads might never report a progress.
                        value: state.uploadProgress != 0
                            ? state.uploadProgress
                            : null),
                  ),
                ),
              );
            }

            return Container();
          },
        ),
      );
}

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:file_picker_cross/file_picker_cross.dart';
import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
          profileBloc: context.bloc<ProfileBloc>(),
          driveDao: context.repository<DriveDao>(),
        ),
        child: BlocConsumer<UploadCubit, UploadState>(
          listener: (context, state) async {
            if (state is UploadComplete) {
              Navigator.pop(context);
            }
          },
          builder: (context, state) {
            if (state is UploadPreparationInProgress) {
              return AlertDialog(
                title: Text('Preparing upload...'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Center(child: CircularProgressIndicator()),
                  ],
                ),
              );
            } else if (state is UploadFileReady) {
              return AlertDialog(
                title: Text('Upload file'),
                content: Text(
                    'This will cost ${utils.winstonToAr(state.uploadCost)} AR.'),
                actions: <Widget>[
                  TextButton(
                    child: Text('CANCEL'),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  TextButton(
                    child: Text('UPLOAD'),
                    onPressed: () => context.bloc<UploadCubit>().startUpload(),
                  ),
                ],
              );
            } else if (state is UploadFileInProgress) {
              return AlertDialog(
                title: Text('Uploading file...'),
                content: ListTile(
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
              );
            }

            return Container();
          },
        ),
      );
}

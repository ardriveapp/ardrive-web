import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:file_picker_cross/file_picker_cross.dart';
import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components.dart';

Future<void> promptToDownloadFile(
  BuildContext context, {
  @required String driveId,
  @required String fileId,
}) =>
    showDialog(
      context: context,
      builder: (_) => FileDownloadDialog(
        driveId: driveId,
        fileId: fileId,
      ),
    );

class FileDownloadDialog extends StatelessWidget {
  final String driveId;
  final String fileId;

  FileDownloadDialog({@required this.driveId, @required this.fileId});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => FileDownloadCubit(
          driveId: driveId,
          fileId: fileId,
          profileCubit: context.bloc<ProfileCubit>(),
          driveDao: context.repository<DriveDao>(),
          arweave: context.repository<ArweaveService>(),
        ),
        child: BlocConsumer<FileDownloadCubit, FileDownloadState>(
          listener: (context, state) async {
            if (state is FileDownloadSuccess) {
              await FilePickerCross(
                state.fileDataBytes,
                path: state.fileName,
                fileExtension: state.fileExtension,
              ).exportToStorage();

              Navigator.pop(context);
            }
          },
          builder: (context, state) => state is FileDownloadInProgress
              ? AppDialog(
                  dismissable: false,
                  title: 'Downloading file...',
                  content: SizedBox(
                    width: kSmallDialogWidth,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        state.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                          '${filesize(state.downloadedByteCount)}/${filesize(state.totalByteCount)}'),
                      trailing: CircularProgressIndicator(
                        // If the download hasn't started yet, show an indeterminate spinner.
                        value: state.downloadProgress != 0
                            ? state.downloadProgress
                            : null,
                      ),
                    ),
                  ),
                )
              : Container(),
        ),
      );
}

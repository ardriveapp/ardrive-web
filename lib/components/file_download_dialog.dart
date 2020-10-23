import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:file_picker_cross/file_picker_cross.dart';
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

  FileDownloadDialog({this.driveId, this.fileId});

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
          builder: (context, state) =>
              ProgressDialog(title: 'Downloading file...'),
        ),
      );
}

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:file_picker_cross/file_picker_cross.dart';
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
            if (state is UploadPreparationInProgress) {
              await showProgressDialog(context, 'Preparing upload...');
            } else if (state is UploadFileReady) {
              Navigator.pop(context);

              var confirm = await showConfirmationDialog(
                context,
                title: 'Upload file',
                content:
                    'This will cost ${utils.winstonToAr(state.uploadCost)} AR.',
                confirmingActionLabel: 'UPLOAD',
              );

              if (confirm != null && confirm) {
                await context.bloc<UploadCubit>().startFileUpload();
              }
            } else if (state is UploadInProgress) {
              await showProgressDialog(context, 'Uploading file...');
            } else if (state is UploadComplete) {
              Navigator.pop(context);
              Navigator.pop(context);
            }
          },
          builder: (context, state) {
            return Container();
          },
        ),
      );
}

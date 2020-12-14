import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components.dart';

Future<void> promptToShareFile({
  @required BuildContext context,
  @required String driveId,
  @required String fileId,
}) =>
    showDialog(
      context: context,
      builder: (_) => BlocProvider<FileShareCubit>(
        create: (_) => FileShareCubit(
          driveId: driveId,
          fileId: fileId,
          profileCubit: context.read<ProfileCubit>(),
          driveDao: context.read<DriveDao>(),
        ),
        child: FileShareDialog(
          driveId: driveId,
          fileId: fileId,
        ),
      ),
    );

class FileShareDialog extends StatefulWidget {
  final String driveId;
  final String fileId;

  FileShareDialog({@required this.driveId, @required this.fileId});

  @override
  _FileShareDialogState createState() => _FileShareDialogState();
}

class _FileShareDialogState extends State<FileShareDialog> {
  final shareLinkController = TextEditingController();

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<FileShareCubit, FileShareState>(
          listener: (context, state) {
            if (state is FileShareLoadSuccess) {
              shareLinkController.text = state.fileShareLink.toString();
            }
          },
          builder: (context, state) => AppDialog(
                dismissable: false,
                title: 'Share file with others',
                content: SizedBox(
                  width: kMediumDialogWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (state is FileShareLoadInProgress)
                        const Center(child: CircularProgressIndicator())
                      else if (state is FileShareLoadSuccess) ...{
                        Text(state.fileName),
                        const SizedBox(height: 16),
                        TextField(
                          controller: shareLinkController,
                          readOnly: true,
                        ),
                      }
                    ],
                  ),
                ),
              ));
}

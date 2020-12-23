import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        child: FileShareDialog(),
      ),
    );

/// Depends on a provided [FileShareCubit] for business logic.
class FileShareDialog extends StatefulWidget {
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
          title: 'Share file with others',
          content: SizedBox(
            width: kLargeDialogWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state is FileShareLoadInProgress)
                  const Center(child: CircularProgressIndicator())
                else if (state is FileShareLoadSuccess) ...{
                  ListTile(
                    title: Text(state.fileName),
                    contentPadding: EdgeInsets.zero,
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: shareLinkController,
                          readOnly: true,
                        ),
                      ),
                      const SizedBox(width: 16),
                      TextButton(
                        child: Text('Copy link'),
                        style: TextButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16)),
                        onPressed: () {
                          // Select the entire link to give the user some feedback on their action.
                          shareLinkController.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: shareLinkController.text.length,
                          );

                          Clipboard.setData(
                              ClipboardData(text: shareLinkController.text));
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Anyone can access this file using the link above.',
                    style: Theme.of(context).textTheme.subtitle2,
                  ),
                }
              ],
            ),
          ),
          actions: [
            if (state is FileShareLoadSuccess)
              ElevatedButton(
                child: Text('DONE'),
                onPressed: () => Navigator.pop(context),
              ),
          ],
        ),
      );
}

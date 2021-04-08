import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components.dart';

Future<void> promptToReuploadFile(
  BuildContext context, {
  @required String driveId,
  @required String folderId,
  @required FileWithLatestRevisionTransactions file,
}) async {
  await showDialog(
    context: context,
    builder: (_) => BlocProvider<RetryUploadCubit>(
      create: (context) => RetryUploadCubit(
        uploadedFile: file,
        arweave: context.read<ArweaveService>(),
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
          if (state is RetryUploadComplete) {
            Navigator.pop(context);
          }
        },
        builder: (context, state) {
          if (state is RetryUploadInProgress) {
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
          } else if (state is RetryUploadFailure) {
            return AppDialog(
              title: 'Failed to reupload files',
              content: SizedBox(
                width: kMediumDialogWidth,
                child: Text(
                  'An error occured while on your file upload. ',
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text('CLOSE'),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            );
          } else if (state is RetryUploadInProgress) {
            return AppDialog(
              dismissable: false,
              title: 'Uploading...',
              content: SizedBox(
                width: kMediumDialogWidth,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 256),
                  child: Scrollbar(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Please wait'),
                          trailing: CircularProgressIndicator(),
                        ),
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

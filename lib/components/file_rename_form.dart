import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

import 'components.dart';

Future<void> promptToRenameFile(
  BuildContext context, {
  @required String driveId,
  @required String fileId,
}) =>
    showDialog(
      context: context,
      builder: (_) => FileRenameForm(
        driveId: driveId,
        fileId: fileId,
      ),
    );

class FileRenameForm extends StatelessWidget {
  final String driveId;
  final String fileId;

  FileRenameForm({@required this.driveId, @required this.fileId});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (context) => FileRenameCubit(
          driveId: driveId,
          fileId: fileId,
          arweave: context.repository<ArweaveService>(),
          driveDao: context.repository<DriveDao>(),
          profileBloc: context.bloc<ProfileBloc>(),
        ),
        child: BlocConsumer<FileRenameCubit, FileRenameState>(
          listener: (context, state) {
            if (state is FileRenameInProgress) {
              showProgressDialog(context, 'Renaming file...');
            } else if (state is FileRenameSuccess) {
              Navigator.pop(context);
              Navigator.pop(context);
            }
          },
          builder: (context, state) => AlertDialog(
            title: Text('Rename file'),
            content: state is! FileRenameInitializing
                ? ReactiveForm(
                    formGroup: context.bloc<FileRenameCubit>().form,
                    child: ReactiveTextField(
                      formControlName: 'name',
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'File name'),
                    ),
                  )
                : null,
            actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0),
            actions: [
              TextButton(
                child: Text('CANCEL'),
                onPressed: () => Navigator.of(context).pop(),
              ),
              TextButton(
                child: Text('RENAME'),
                onPressed: () => context.bloc<FileRenameCubit>().submit(),
              ),
            ],
          ),
        ),
      );
}

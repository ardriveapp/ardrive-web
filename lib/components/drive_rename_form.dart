import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/drive_rename/drive_rename_cubit.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

import 'components.dart';

Future<void> promptToRenameDrive(
  BuildContext context, {
  required String driveId,
}) =>
    showDialog(
      context: context,
      builder: (_) => BlocProvider(
        create: (context) => DriveRenameCubit(
          driveId: driveId,
          arweave: context.read<ArweaveService>(),
          driveDao: context.read<DriveDao>(),
          profileCubit: context.read<ProfileCubit>(),
          syncCubit: context.read<SyncCubit>(),
        ),
        child: DriveRenameForm(),
      ),
    );

class DriveRenameForm extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      BlocConsumer<DriveRenameCubit, DriveRenameState>(
        listener: (context, state) {
          if (state is DriveRenameInProgress) {
            showProgressDialog(context, 'RENAMING DRIVE...');
          } else if (state is DriveRenameSuccess) {
            Navigator.pop(context);
            Navigator.pop(context);
          } else if (state is DriveRenameWalletMismatch) {
            Navigator.pop(context);
          }
        },
        builder: (context, state) => AppDialog(
          title: 'RENAME DRIVE',
          content: state is! FsEntryRenameInitializing
              ? SizedBox(
                  width: kMediumDialogWidth,
                  child: ReactiveForm(
                    formGroup: context.watch<DriveRenameCubit>().form,
                    child: ReactiveTextField(
                      formControlName: 'name',
                      autofocus: true,
                      decoration: InputDecoration(labelText: 'Drive name'),
                      showErrors: (control) => control.invalid,
                      validationMessages: (_) => kValidationMessages,
                    ),
                  ),
                )
              : null,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () => context.read<DriveRenameCubit>().submit(),
              child: Text('RENAME'),
            ),
          ],
        ),
      );
}

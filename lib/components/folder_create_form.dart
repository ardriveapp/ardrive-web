import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

import '../../../utils/app_localizations_wrapper.dart';
import 'components.dart';

Future<void> promptToCreateFolder(
  BuildContext context, {
  required String driveId,
  required String parentFolderId,
}) =>
    showCongestionDependentModalDialog(
      context,
      () => showDialog(
        context: context,
        builder: (_) => BlocProvider(
          create: (context) => FolderCreateCubit(
            driveId: driveId,
            parentFolderId: parentFolderId,
            profileCubit: context.read<ProfileCubit>(),
            arweave: context.read<ArweaveService>(),
            driveDao: context.read<DriveDao>(),
          ),
          child: FolderCreateForm(),
        ),
      ),
    );

Future<void> promptToCreateFolderWithoutCongestionWarning(
  BuildContext context, {
  required String driveId,
  required String parentFolderId,
}) =>
    showDialog(
      context: context,
      builder: (_) => BlocProvider(
        create: (context) => FolderCreateCubit(
          driveId: driveId,
          parentFolderId: parentFolderId,
          profileCubit: context.read<ProfileCubit>(),
          arweave: context.read<ArweaveService>(),
          driveDao: context.read<DriveDao>(),
        ),
        child: FolderCreateForm(),
      ),
    );

class FolderCreateForm extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      BlocConsumer<FolderCreateCubit, FolderCreateState>(
        listener: (context, state) {
          if (state is FolderCreateInProgress) {
            showProgressDialog(
                context, appLocalizationsOf(context).creatingFolderEmphasized);
          } else if (state is FolderCreateSuccess) {
            Navigator.pop(context);
            Navigator.pop(context);
          } else if (state is FolderCreateWalletMismatch) {
            Navigator.pop(context);
          }
        },
        builder: (context, state) => AppDialog(
          title: appLocalizationsOf(context).createFolderEmphasized,
          content: SizedBox(
            width: kMediumDialogWidth,
            child: ReactiveForm(
              formGroup: context.watch<FolderCreateCubit>().form,
              child: ReactiveTextField(
                formControlName: 'name',
                autofocus: true,
                decoration: InputDecoration(
                    labelText: appLocalizationsOf(context).folderName),
                showErrors: (control) => control.dirty && control.invalid,
                validationMessages: (_) => kValidationMessages,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text(
                  appLocalizationsOf(context).cancelFolderCreateEmphasized),
            ),
            ElevatedButton(
              onPressed: () => context.read<FolderCreateCubit>().submit(),
              child: Text(appLocalizationsOf(context).createEmphasized),
            ),
          ],
        ),
      );
}

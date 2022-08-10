import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

import 'components.dart';

Future<void> promptToRenameFolder(
  BuildContext context, {
  required String driveId,
  required String folderId,
}) =>
    showCongestionDependentModalDialog(
      context,
      () => showDialog(
        context: context,
        builder: (_) => BlocProvider(
          create: (context) => FsEntryRenameCubit(
            driveId: driveId,
            folderId: folderId,
            arweave: context.read<ArweaveService>(),
            driveDao: context.read<DriveDao>(),
            profileCubit: context.read<ProfileCubit>(),
            syncCubit: context.read<SyncCubit>(),
          ),
          child: const FsEntryRenameForm(),
        ),
      ),
    );

Future<void> promptToRenameFile(
  BuildContext context, {
  required String driveId,
  required String fileId,
}) =>
    showCongestionDependentModalDialog(
        context,
        () => showDialog(
              context: context,
              builder: (_) => BlocProvider(
                create: (context) => FsEntryRenameCubit(
                  driveId: driveId,
                  fileId: fileId,
                  arweave: context.read<ArweaveService>(),
                  driveDao: context.read<DriveDao>(),
                  profileCubit: context.read<ProfileCubit>(),
                  syncCubit: context.read<SyncCubit>(),
                ),
                child: const FsEntryRenameForm(),
              ),
            ));

class FsEntryRenameForm extends StatelessWidget {
  const FsEntryRenameForm({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<FsEntryRenameCubit, FsEntryRenameState>(
        listener: (context, state) {
          if (state is FolderEntryRenameInProgress) {
            showProgressDialog(
                context, appLocalizationsOf(context).renamingFolderEmphasized);
          } else if (state is FileEntryRenameInProgress) {
            showProgressDialog(
                context, appLocalizationsOf(context).renamingFileEmphasized);
          } else if (state is FolderEntryRenameSuccess ||
              state is FileEntryRenameSuccess) {
            Navigator.pop(context);
            Navigator.pop(context);
          } else if (state is FolderEntryRenameWalletMismatch ||
              state is FileEntryRenameWalletMismatch) {
            Navigator.pop(context);
          }
        },
        builder: (context, state) => AppDialog(
          title: state.isRenamingFolder
              ? appLocalizationsOf(context).renameFolderEmphasized
              : appLocalizationsOf(context).renameFileEmphasized,
          content: state is! FsEntryRenameInitializing
              ? SizedBox(
                  width: kMediumDialogWidth,
                  child: ReactiveForm(
                    formGroup: context.watch<FsEntryRenameCubit>().form,
                    child: ReactiveTextField(
                      formControlName: 'name',
                      autofocus: true,
                      decoration: InputDecoration(
                          labelText: state.isRenamingFolder
                              ? appLocalizationsOf(context).folderName
                              : appLocalizationsOf(context).fileName),
                      showErrors: (control) => control.invalid,
                      validationMessages:
                          kValidationMessages(appLocalizationsOf(context)),
                    ),
                  ),
                )
              : Container(),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(appLocalizationsOf(context).cancelEmphasized),
            ),
            ElevatedButton(
              onPressed: () => context.read<FsEntryRenameCubit>().submit(),
              child: Text(appLocalizationsOf(context).renameEmphasized),
            ),
          ],
        ),
      );
}

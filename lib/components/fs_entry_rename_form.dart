import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
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
          child: FsEntryRenameForm(),
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
                child: FsEntryRenameForm(),
              ),
            ));

class FsEntryRenameForm extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      BlocConsumer<FsEntryRenameCubit, FsEntryRenameState>(
        listener: (context, state) {
          if (state is FolderEntryRenameInProgress) {
            showProgressDialog(context,
                AppLocalizations.of(context)!.renamingFolderEmphasized);
          } else if (state is FileEntryRenameInProgress) {
            showProgressDialog(
                context, AppLocalizations.of(context)!.renamingFileEmphasized);
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
              ? AppLocalizations.of(context)!.renameFolderEmphasized
              : AppLocalizations.of(context)!.renameFileEmphasized,
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
                              ? AppLocalizations.of(context)!.folderName
                              : AppLocalizations.of(context)!.fileName),
                      showErrors: (control) => control.invalid,
                      validationMessages: (_) => kValidationMessages,
                    ),
                  ),
                )
              : Container(),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(AppLocalizations.of(context)!.cancelRenameEmphasized),
            ),
            ElevatedButton(
              onPressed: () => context.read<FsEntryRenameCubit>().submit(),
              child: Text(AppLocalizations.of(context)!.renameEmphasized),
            ),
          ],
        ),
      );
}

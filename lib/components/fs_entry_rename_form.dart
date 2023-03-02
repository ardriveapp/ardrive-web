import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components.dart';

void showRenameModal(
  BuildContext context, {
  required String driveId,
  String? folderId,
  String? fileId,
}) {
  showAnimatedDialog(
    context,
    content: BlocProvider(
      create: (context) => FsEntryRenameCubit(
        crypto: ArDriveCrypto(),
        driveId: driveId,
        folderId: folderId,
        fileId: fileId,
        arweave: context.read<ArweaveService>(),
        turboService: context.read<TurboService>(),
        driveDao: context.read<DriveDao>(),
        profileCubit: context.read<ProfileCubit>(),
        syncCubit: context.read<SyncCubit>(),
      ),
      child: const FsEntryRenameForm(),
    ),
  );
}

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
            crypto: ArDriveCrypto(),
            driveId: driveId,
            folderId: folderId,
            arweave: context.read<ArweaveService>(),
            turboService: context.read<TurboService>(),
            driveDao: context.read<DriveDao>(),
            profileCubit: context.read<ProfileCubit>(),
            syncCubit: context.read<SyncCubit>(),
          ),
          child: const FsEntryRenameForm(),
        ),
      ),
    );

class FsEntryRenameForm extends StatefulWidget {
  const FsEntryRenameForm({Key? key}) : super(key: key);

  @override
  State<FsEntryRenameForm> createState() => _FsEntryRenameFormState();
}

class _FsEntryRenameFormState extends State<FsEntryRenameForm> {
  final _nameController = TextEditingController();

  bool _validForm = false;

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<FsEntryRenameCubit, FsEntryRenameState>(
        listener: (context, state) {
          if (state is FolderEntryRenameInProgress) {
            showNewProgressDialog(context,
                title: appLocalizationsOf(context).renamingFolderEmphasized);
          } else if (state is FileEntryRenameInProgress) {
            showNewProgressDialog(
              context,
              title: appLocalizationsOf(context).renamingFileEmphasized,
            );
          } else if (state is FolderEntryRenameSuccess ||
              state is FileEntryRenameSuccess) {
            Navigator.pop(context);
            Navigator.pop(context);
          } else if (state is FolderEntryRenameWalletMismatch ||
              state is FileEntryRenameWalletMismatch) {
            Navigator.pop(context);
          } else if (state is FsEntryRenameInitialized) {
            _nameController.text = state.entryName;
          }
        },
        builder: (context, state) => ArDriveStandardModal(
          title: state.isRenamingFolder
              ? appLocalizationsOf(context).renameFolderEmphasized
              : appLocalizationsOf(context).renameFileEmphasized,
          content: state is! FsEntryRenameInitializing
              ? SizedBox(
                  width: kMediumDialogWidth,
                  child: ArDriveTextField(
                    controller: _nameController,
                    autofocus: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        setState(() {
                          _validForm = false;
                        });
                        return appLocalizationsOf(context).validationRequired;
                      } else if (value == state.entryName) {
                        setState(() {
                          _validForm = false;
                        });
                        return appLocalizationsOf(context)
                            .validationNameUnchanged;
                      }

                      setState(() {
                        _validForm = true;
                      });
                      return null;
                    },
                  ),
                )
              : Container(),
          actions: [
            ModalAction(
                action: () => Navigator.of(context).pop(),
                title: appLocalizationsOf(context).cancelEmphasized),
            ModalAction(
              action: () => context
                  .read<FsEntryRenameCubit>()
                  .submit(_nameController.text),
              title: appLocalizationsOf(context).renameEmphasized,
              isEnable: _validForm,
            ),
          ],
        ),
      );
}

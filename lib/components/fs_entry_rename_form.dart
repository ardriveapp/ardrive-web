import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/progress_dialog.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/validate_folder_name.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

void promptToRenameModal(
  BuildContext context, {
  required String driveId,
  String? folderId,
  String? fileId,
  required String initialName,
}) {
  showAnimatedDialog(
    context,
    content: MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => FsEntryRenameCubit(
            crypto: ArDriveCrypto(),
            driveId: driveId,
            folderId: folderId,
            fileId: fileId,
            arweave: context.read<ArweaveService>(),
            turboUploadService: context.read<UploadService>(),
            driveDao: context.read<DriveDao>(),
            profileCubit: context.read<ProfileCubit>(),
            syncCubit: context.read<SyncCubit>(),
          ),
        ),
        BlocProvider.value(
          value: context.read<DriveDetailCubit>(),
        ),
      ],
      child: FsEntryRenameForm(
        entryName: initialName,
      ),
    ),
  );
}

class FsEntryRenameForm extends StatefulWidget {
  const FsEntryRenameForm({
    Key? key,
    required this.entryName,
  }) : super(key: key);

  final String entryName;

  @override
  State<FsEntryRenameForm> createState() => _FsEntryRenameFormState();
}

class _FsEntryRenameFormState extends State<FsEntryRenameForm> {
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.entryName;
  }

  bool _validForm = false;

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<FsEntryRenameCubit, FsEntryRenameState>(
        listener: (context, state) {
          if (state is FolderEntryRenameInProgress) {
            showProgressDialog(
              context,
              title: appLocalizationsOf(context).renamingFolderEmphasized,
            );
          } else if (state is FileEntryRenameInProgress) {
            showProgressDialog(
              context,
              title: appLocalizationsOf(context).renamingFileEmphasized,
            );
          } else if (state is FolderEntryRenameSuccess ||
              state is FileEntryRenameSuccess) {
            context.read<DriveDetailCubit>().refreshDriveDataTable();

            Navigator.pop(context);
            Navigator.pop(context);
          } else if (state is FolderEntryRenameWalletMismatch ||
              state is FileEntryRenameWalletMismatch) {
            Navigator.pop(context);
          } else if (state is FsEntryRenameInitialized) {
            _nameController.text = widget.entryName;
          } else if (state is EntityAlreadyExists) {
            showAnimatedDialog(
              context,
              content: ArDriveStandardModal(
                title: appLocalizationsOf(context).error,
                description: appLocalizationsOf(context).entityAlreadyExists(
                  state.entityName,
                ),
              ),
            );
          }
        },
        builder: (context, state) {
          return ArDriveStandardModal(
            title: state.isRenamingFolder
                ? appLocalizationsOf(context).renameFolderEmphasized
                : appLocalizationsOf(context).renameFileEmphasized,
            content: state is! FsEntryRenameInitializing
                ? SizedBox(
                    width: kMediumDialogWidth,
                    child: ArDriveTextField(
                      controller: _nameController,
                      autofocus: true,
                      onFieldSubmitted: (value) {
                        if (_validForm) {
                          context
                              .read<FsEntryRenameCubit>()
                              .submit(newName: value);
                        }
                      },
                      validator: (value) {
                        final validation = validateEntityName(value, context);

                        if (validation == null) {
                          setState(() => _validForm = true);
                        } else {
                          setState(() => _validForm = false);
                        }

                        return validation;
                      },
                    ),
                  )
                : Container(),
            actions: [
              ModalAction(
                action: () => Navigator.of(context).pop(),
                title: appLocalizationsOf(context).cancelEmphasized,
              ),
              ModalAction(
                action: () => context
                    .read<FsEntryRenameCubit>()
                    .submit(newName: _nameController.text),
                title: appLocalizationsOf(context).renameEmphasized,
                isEnable: _validForm,
              ),
            ],
          );
        },
      );
}

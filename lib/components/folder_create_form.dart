import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/validate_folder_name.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components.dart';

Future<void> promptToCreateFolder(
  BuildContext context, {
  required String driveId,
  required String parentFolderId,
}) =>
    showArDriveDialog(
      context,
      content: BlocProvider(
        create: (context) => FolderCreateCubit(
          driveId: driveId,
          parentFolderId: parentFolderId,
          profileCubit: context.read<ProfileCubit>(),
          arweave: context.read<ArweaveService>(),
          turboUploadService: context.read<TurboUploadService>(),
          driveDao: context.read<DriveDao>(),
        ),
        child: const FolderCreateForm(),
      ),
    );

Future<void> promptToCreateFolderWithoutCongestionWarning(
  BuildContext context, {
  required String driveId,
  required String parentFolderId,
}) =>
    showArDriveDialog(
      context,
      content: BlocProvider(
        create: (context) => FolderCreateCubit(
          driveId: driveId,
          parentFolderId: parentFolderId,
          profileCubit: context.read<ProfileCubit>(),
          arweave: context.read<ArweaveService>(),
          turboUploadService: context.read<TurboUploadService>(),
          driveDao: context.read<DriveDao>(),
        ),
        child: const FolderCreateForm(),
      ),
    );

class FolderCreateForm extends StatefulWidget {
  const FolderCreateForm({super.key});

  @override
  State<FolderCreateForm> createState() => _FolderCreateFormState();
}

class _FolderCreateFormState extends State<FolderCreateForm> {
  final TextEditingController _folderNameController = TextEditingController();

  bool _isFolderNameValid = false;

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<FolderCreateCubit, FolderCreateState>(
        listener: (context, state) {
          if (state is FolderCreateInProgress) {
            showProgressDialog(
              context,
              title: appLocalizationsOf(context).creatingFolderEmphasized,
              useNewArDriveUI: true,
            );
          } else if (state is FolderCreateSuccess) {
            Navigator.pop(context);
            Navigator.pop(context);
          } else if (state is FolderCreateWalletMismatch) {
            Navigator.pop(context);
          } else if (state is FolderCreateNameAlreadyExists) {
            Navigator.pop(context);

            showStandardDialog(
              context,
              title: appLocalizationsOf(context).error,
              description: appLocalizationsOf(context).entityAlreadyExists(
                state.folderName,
              ),
              useNewArDriveUI: true,
            );
          }
        },
        builder: (context, state) => ArDriveStandardModalNew(
          title: appLocalizationsOf(context).createFolderEmphasized,
          content: SizedBox(
            width: kMediumDialogWidth,
            child: ArDriveTextFieldNew(
              controller: _folderNameController,
              autofocus: true,
              onFieldSubmitted: (value) {
                if (_isFolderNameValid) {
                  context.read<FolderCreateCubit>().submit(folderName: value);
                }
              },
              validator: (value) {
                final validation = validateEntityName(value, context);

                if (validation == null) {
                  setState(() => _isFolderNameValid = true);
                } else {
                  setState(() => _isFolderNameValid = false);
                }

                return validation;
              },
            ),
          ),
          actions: [
            ModalAction(
              action: () => Navigator.of(context).pop(null),
              title: appLocalizationsOf(context).cancelEmphasized,
            ),
            ModalAction(
              isEnable: _isFolderNameValid,
              action: () => context
                  .read<FolderCreateCubit>()
                  .submit(folderName: _folderNameController.text),
              title: appLocalizationsOf(context).createEmphasized,
            ),
          ],
        ),
      );
}

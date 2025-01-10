import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/drive_rename/drive_rename_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/validate_folder_name.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components.dart';

Future<void> promptToRenameDrive(
  BuildContext context, {
  required String driveId,
  required String driveName,
}) =>
    showCongestionDependentModalDialog(
      context,
      () => showArDriveDialog(
        context,
        content: MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (context) => DriveRenameCubit(
                driveId: driveId,
                arweave: context.read<ArweaveService>(),
                turboUploadService: context.read<TurboUploadService>(),
                driveDao: context.read<DriveDao>(),
                profileCubit: context.read<ProfileCubit>(),
                syncCubit: context.read<SyncCubit>(),
              ),
            ),
            BlocProvider.value(
              value: context.read<DriveDetailCubit>(),
            ),
          ],
          child: DriveRenameForm(
            driveName: driveName,
          ),
        ),
      ),
    );

class DriveRenameForm extends StatefulWidget {
  const DriveRenameForm({
    super.key,
    required this.driveName,
  });

  final String driveName;

  @override
  State<DriveRenameForm> createState() => _DriveRenameFormState();
}

class _DriveRenameFormState extends State<DriveRenameForm> {
  bool _isFolderNameValid = false;
  final controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    controller.text = widget.driveName;
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<DriveRenameCubit, DriveRenameState>(
        listener: (context, state) {
          if (state is DriveRenameInProgress) {
            showProgressDialog(
              context,
              title: appLocalizationsOf(context).renamingDriveEmphasized,
              useNewArDriveUI: true,
            );
          } else if (state is DriveRenameSuccess) {
            context.read<DriveDetailCubit>().refreshDriveDataTable();
            Navigator.pop(context);
            Navigator.pop(context);
          } else if (state is DriveRenameWalletMismatch) {
            Navigator.pop(context);
          } else if (state is DriveNameAlreadyExists) {
            showStandardDialog(
              context,
              title: 'Warning',
              description:
                  'A drive with this name already exists. Do you want to proceed?',
              useNewArDriveUI: true,
              actions: [
                ModalAction(
                  action: () => Navigator.of(context).pop(),
                  title: 'Cancel',
                ),
                ModalAction(
                  action: () {
                    Navigator.of(context).pop();
                    return context.read<DriveRenameCubit>().submit(
                          newName: controller.text,
                          proceedIfHasConflicts: true,
                        );
                  },
                  title: 'Proceed',
                ),
              ],
            );
          }
        },
        builder: (context, state) => ArDriveStandardModalNew(
          title: appLocalizationsOf(context).renameDriveEmphasized,
          content: state is! FsEntryRenameInitializing
              ? SizedBox(
                  width: kMediumDialogWidth,
                  child: ArDriveTextFieldNew(
                    controller: controller,
                    autofocus: true,
                    validator: (value) {
                      if (value == widget.driveName) {
                        return appLocalizationsOf(context)
                            .validationNameUnchanged;
                      }

                      final validation = validateEntityName(value, context);

                      if (validation == null) {
                        setState(() => _isFolderNameValid = true);
                      } else {
                        setState(() => _isFolderNameValid = false);
                      }

                      return validation;
                    },
                  ),
                )
              : Container(),
          actions: [
            ModalAction(
                action: () => Navigator.of(context).pop(),
                title: appLocalizationsOf(context).cancelEmphasized),
            ModalAction(
              isEnable: _isFolderNameValid,
              action: () => context.read<DriveRenameCubit>().submit(
                    newName: controller.text,
                  ),
              title: appLocalizationsOf(context).renameEmphasized,
            ),
          ],
        ),
      );
}

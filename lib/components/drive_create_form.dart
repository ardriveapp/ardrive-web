import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/validate_folder_name.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

import 'components.dart';

Future<void> promptToCreateDrive(BuildContext context) =>
    showCongestionDependentModalDialog(
      context,
      () => showAnimatedDialog(
        context,
        content: BlocProvider(
          create: (_) => DriveCreateCubit(
            arweave: context.read<ArweaveService>(),
            turboUploadService: context.read<TurboUploadService>(),
            driveDao: context.read<DriveDao>(),
            profileCubit: context.read<ProfileCubit>(),
            drivesCubit: context.read<DrivesCubit>(),
          ),
          child: const DriveCreateForm(),
        ),
      ),
    );

class DriveCreateForm extends StatefulWidget {
  const DriveCreateForm({Key? key}) : super(key: key);

  @override
  State<DriveCreateForm> createState() => _DriveCreateFormState();
}

class _DriveCreateFormState extends State<DriveCreateForm> {
  final _driveNameController = TextEditingController();
  bool _isDriveNameValid = false;

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<DriveCreateCubit, DriveCreateState>(
        listener: (context, state) {
          if (state is DriveCreateInProgress) {
            showProgressDialog(
              context,
              title: appLocalizationsOf(context).creatingDriveEmphasized,
            );
          } else if (state is DriveCreateSuccess) {
            Navigator.pop(context);
            Navigator.pop(context);
          } else if (state is DriveCreateWalletMismatch) {
            Navigator.pop(context);
          }
        },
        builder: (context, state) {
          if (state is DriveCreateZeroBalance) {
            return ArDriveStandardModal(
              title: appLocalizationsOf(context).createDriveEmphasized,
              description:
                  appLocalizationsOf(context).insufficientARToCreateDrive,
              actions: [
                ModalAction(
                  action: () => Navigator.of(context).pop(),
                  title: appLocalizationsOf(context).cancelEmphasized,
                ),
              ],
            );
          } else {
            final privacy = state.privacy;

            return ArDriveStandardModal(
              title: appLocalizationsOf(context).createDriveEmphasized,
              content: SizedBox(
                width: kMediumDialogWidth,
                child: ReactiveForm(
                  formGroup: context.watch<DriveCreateCubit>().form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ArDriveTextField(
                        controller: _driveNameController,
                        autofocus: true,
                        onFieldSubmitted: (value) {
                          if (_isDriveNameValid) {
                            context
                                .read<FolderCreateCubit>()
                                .submit(folderName: value);
                          }
                        },
                        validator: (value) {
                          final validation = validateEntityName(value, context);

                          if (validation == null) {
                            setState(() => _isDriveNameValid = true);
                          } else {
                            setState(() => _isDriveNameValid = false);
                          }

                          return validation;
                        },
                      ),
                      const SizedBox(height: 16),
                      ReactiveDropdownField(
                        formControlName: 'privacy',
                        decoration: InputDecoration(
                          label: Text(
                            appLocalizationsOf(context).privacy,
                            style: ArDriveTheme.of(context)
                                .themeData
                                .textFieldTheme
                                .inputTextStyle
                                .copyWith(
                                  color: ArDriveTheme.of(context)
                                      .themeData
                                      .colors
                                      .themeFgDisabled,
                                  fontSize: 16,
                                ),
                          ),
                          focusedBorder: InputBorder.none,
                        ),
                        showErrors: (control) =>
                            control.dirty && control.invalid,
                        validationMessages:
                            kValidationMessages(appLocalizationsOf(context)),
                        items: [
                          DropdownMenuItem(
                            value: DrivePrivacy.public.name,
                            child: Text(appLocalizationsOf(context).public),
                          ),
                          DropdownMenuItem(
                            value: DrivePrivacy.private.name,
                            child: Text(
                              appLocalizationsOf(context).private,
                            ),
                          )
                        ],
                        onChanged: (_) {
                          context.read<DriveCreateCubit>().onPrivacyChanged();
                        },
                      ),
                      const SizedBox(height: 32),
                      Row(children: [
                        if (privacy == DrivePrivacy.private)
                          Flexible(
                              child: Text(
                            appLocalizationsOf(context)
                                .drivePrivacyDescriptionPrivate,
                          ))
                        else
                          Flexible(
                              child: Text(
                            appLocalizationsOf(context)
                                .drivePrivacyDescriptionPublic,
                          ))
                      ]),
                    ],
                  ),
                ),
              ),
              actions: [
                ModalAction(
                  action: () => Navigator.of(context).pop(),
                  title: appLocalizationsOf(context).cancelEmphasized,
                ),
                ModalAction(
                  isEnable: _isDriveNameValid,
                  action: () => context.read<DriveCreateCubit>().submit(
                        _driveNameController.text,
                      ),
                  title: appLocalizationsOf(context).createEmphasized,
                ),
              ],
            );
          }
        },
      );
}

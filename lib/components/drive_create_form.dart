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

Future<void> promptToCreateDrive(BuildContext context) =>
    showCongestionDependentModalDialog(
      context,
      () => showDialog(
        context: context,
        builder: (BuildContext context) => BlocProvider(
          create: (_) => DriveCreateCubit(
            arweave: context.read<ArweaveService>(),
            turboService: context.read<TurboService>(),
            driveDao: context.read<DriveDao>(),
            profileCubit: context.read<ProfileCubit>(),
            drivesCubit: context.read<DrivesCubit>(),
          ),
          child: const DriveCreateForm(),
        ),
      ),
    );

class DriveCreateForm extends StatelessWidget {
  const DriveCreateForm({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<DriveCreateCubit, DriveCreateState>(
        listener: (context, state) {
          if (state is DriveCreateInProgress) {
            showProgressDialog(
                context, appLocalizationsOf(context).creatingDriveEmphasized);
          } else if (state is DriveCreateSuccess) {
            Navigator.pop(context);
            Navigator.pop(context);
          } else if (state is DriveCreateWalletMismatch) {
            Navigator.pop(context);
          }
        },
        builder: (context, state) {
          if (state is DriveCreateZeroBalance) {
            return AppDialog(
              title: appLocalizationsOf(context).createDriveEmphasized,
              content: SizedBox(
                  width: kMediumDialogWidth,
                  child: Text(
                      appLocalizationsOf(context).insufficientARToCreateDrive)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(appLocalizationsOf(context).cancelEmphasized),
                ),
              ],
            );
          } else {
            return AppDialog(
              title: appLocalizationsOf(context).createDriveEmphasized,
              content: SizedBox(
                width: kMediumDialogWidth,
                child: ReactiveForm(
                  formGroup: context.watch<DriveCreateCubit>().form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ReactiveTextField(
                        formControlName: 'name',
                        autofocus: true,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                            labelText: appLocalizationsOf(context).name),
                        showErrors: (control) =>
                            control.dirty && control.invalid,
                        validationMessages:
                            kValidationMessages(appLocalizationsOf(context)),
                      ),
                      const SizedBox(height: 16),
                      ReactiveDropdownField(
                        formControlName: 'privacy',
                        decoration: InputDecoration(
                            labelText: appLocalizationsOf(context).privacy),
                        showErrors: (control) =>
                            control.dirty && control.invalid,
                        validationMessages:
                            kValidationMessages(appLocalizationsOf(context)),
                        items: [
                          DropdownMenuItem(
                            value: 'public',
                            child: Text(appLocalizationsOf(context).public),
                          ),
                          DropdownMenuItem(
                            value: 'private',
                            child: Text(appLocalizationsOf(context).private),
                          )
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(appLocalizationsOf(context).cancelEmphasized),
                ),
                ElevatedButton(
                  onPressed: () => context.read<DriveCreateCubit>().submit(),
                  child: Text(appLocalizationsOf(context).createEmphasized),
                ),
              ],
            );
          }
        },
      );
}

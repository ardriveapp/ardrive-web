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

Future<void> promptToCreateDrive(BuildContext context) =>
    showCongestionDependentModalDialog(
      context,
      () => showDialog(
        context: context,
        builder: (BuildContext context) => BlocProvider(
          create: (_) => DriveCreateCubit(
            arweave: context.read<ArweaveService>(),
            driveDao: context.read<DriveDao>(),
            profileCubit: context.read<ProfileCubit>(),
            drivesCubit: context.read<DrivesCubit>(),
          ),
          child: DriveCreateForm(),
        ),
      ),
    );

class DriveCreateForm extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      BlocConsumer<DriveCreateCubit, DriveCreateState>(
        listener: (context, state) {
          if (state is DriveCreateInProgress) {
            showProgressDialog(context,
                AppLocalizations.of(context)!.creatingDrive.toUpperCase());
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
              title: AppLocalizations.of(context)!.createDrive.toUpperCase(),
              content: SizedBox(
                  width: kMediumDialogWidth,
                  child: Text(AppLocalizations.of(context)!
                      .insufficientARToCreateDrive)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child:
                      Text(AppLocalizations.of(context)!.cancelDriveCreation),
                ),
              ],
            );
          } else {
            return AppDialog(
              title: AppLocalizations.of(context)!.createDrive.toUpperCase(),
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
                            labelText: AppLocalizations.of(context)!.name),
                        showErrors: (control) =>
                            control.dirty && control.invalid,
                        validationMessages: (_) => kValidationMessages,
                      ),
                      const SizedBox(height: 16),
                      ReactiveDropdownField(
                        formControlName: 'privacy',
                        decoration: InputDecoration(
                            labelText: AppLocalizations.of(context)!.privacy),
                        showErrors: (control) =>
                            control.dirty && control.invalid,
                        validationMessages: (_) => kValidationMessages,
                        items: [
                          DropdownMenuItem(
                            value: 'public',
                            child: Text(AppLocalizations.of(context)!.public),
                          ),
                          DropdownMenuItem(
                            value: 'private',
                            child: Text(AppLocalizations.of(context)!.private),
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
                  child: Text(AppLocalizations.of(context)!
                      .cancelDriveCreation
                      .toUpperCase()),
                ),
                ElevatedButton(
                  onPressed: () => context.read<DriveCreateCubit>().submit(),
                  child: Text(AppLocalizations.of(context)!.create),
                ),
              ],
            );
          }
        },
      );
}

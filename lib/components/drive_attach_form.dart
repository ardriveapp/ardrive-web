import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/user_interaction_wrapper.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// ignore: unused_import
import 'package:meta/meta.dart';
import 'package:reactive_forms/reactive_forms.dart';

import '../../../utils/app_localizations_wrapper.dart';
import 'components.dart';

Future<void> attachDrive({
  required BuildContext context,
  DriveID? driveId,
  String? driveName,
  SecretKey? driveKey,
}) {
  final profileState = context.read<ProfileCubit>().state;
  final profileKey =
      profileState is ProfileLoggedIn ? profileState.cipherKey : null;
  return showModalDialog(
    context,
    () => showDialog(
      context: context,
      builder: (BuildContext context) => BlocProvider<DriveAttachCubit>(
        create: (context) => DriveAttachCubit(
          initialDriveId: driveId,
          initialDriveName: driveName,
          initialDriveKey: driveKey,
          arweave: context.read<ArweaveService>(),
          driveDao: context.read<DriveDao>(),
          syncBloc: context.read<SyncCubit>(),
          drivesBloc: context.read<DrivesCubit>(),
          profileKey: profileKey,
        ),
        child: BlocListener<DriveAttachCubit, DriveAttachState>(
          listener: (context, state) {
            if (state is DriveAttachFailure || state is DriveAttachSuccess) {
              // Close the progress dialog if the drive attachment fails or succeeds.
              Navigator.pop(context);
            }
          },
          child: DriveAttachForm(),
        ),
      ),
    ),
  );
}

/// Depends on a provided [DriveAttachCubit] for business logic.
class DriveAttachForm extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DriveAttachCubit, DriveAttachState>(
      builder: (context, state) {
        if (state is DriveAttachInProgress) {
          return ProgressDialog(
            title: appLocalizationsOf(context).attachingDriveEmphasized,
          );
        }

        return AppDialog(
          title: appLocalizationsOf(context).attachDriveEmphasized,
          content: SizedBox(
            width: kMediumDialogWidth,
            child: ReactiveForm(
              formGroup: context.watch<DriveAttachCubit>().form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ReactiveTextField(
                    formControlName: 'driveId',
                    autofocus: true,
                    decoration: InputDecoration(
                        labelText: appLocalizationsOf(context).driveID),
                    validationMessages: (_) => kValidationMessages,
                  ),
                  const SizedBox(height: 16),
                  if (state is DriveAttachPrivate)
                    ReactiveTextField(
                      formControlName: 'driveKey',
                      autofocus: true,
                      obscureText: true,
                      decoration: InputDecoration(labelText: 'Drive Key'),
                      validationMessages: (_) => kValidationMessages,
                      onEditingComplete: () => context
                          .read<DriveAttachCubit>()
                          .form
                          .updateValueAndValidity(),
                    ),
                  const SizedBox(height: 16),
                  ReactiveTextField(
                    formControlName: 'name',
                    decoration: InputDecoration(
                      labelText: appLocalizationsOf(context).name,
                      // Listen to `driveId` status changes to show an indicator for
                      // when the drive name is being loaded.
                      //
                      // Use `suffixIcon` here to prevent indicator from being hidden when
                      // input is unfocused.
                      suffixIcon: StreamBuilder<ControlStatus>(
                        stream: context
                            .watch<DriveAttachCubit>()
                            .form
                            .control('driveId')
                            .statusChanged,
                        builder: (context, driveIdControlStatusSnapshot) =>
                            driveIdControlStatusSnapshot.data ==
                                    ControlStatus.pending
                                ? const Padding(
                                    padding: EdgeInsets.only(right: 8),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                : const SizedBox(),
                      ),
                      // Account for the progress indicator padding in the constraints.
                      suffixIconConstraints:
                          const BoxConstraints.tightFor(width: 32, height: 24),
                    ),
                    validationMessages: (_) => kValidationMessages,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text(appLocalizationsOf(context).cancelEmphasized),
            ),
            ElevatedButton(
              onPressed: () => context.read<DriveAttachCubit>().submit(),
              child: Text(appLocalizationsOf(context).attachEmphasized),
            ),
          ],
        );
      },
    );
  }
}

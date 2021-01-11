import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:reactive_forms/reactive_forms.dart';

import 'components.dart';

Future<void> promptToAttachDrive(
        {@required BuildContext context, String initialDriveId}) =>
    showDialog(
      context: context,
      builder: (BuildContext context) => BlocProvider<DriveAttachCubit>(
        create: (context) => DriveAttachCubit(
          initialDriveId: initialDriveId,
          arweave: context.read<ArweaveService>(),
          driveDao: context.read<DriveDao>(),
          syncBloc: context.read<SyncCubit>(),
          drivesBloc: context.read<DrivesCubit>(),
        ),
        child: DriveAttachForm(),
      ),
    );

/// Depends on a provided [DriveAttachCubit] for business logic.
class DriveAttachForm extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      BlocConsumer<DriveAttachCubit, DriveAttachState>(
        listener: (context, state) {
          if (state is DriveAttachInProgress) {
            showProgressDialog(context, 'ATTACHING DRIVE...');
          } else if (state is DriveAttachFailure) {
            // Close the progress dialog if the drive attachment fails.
            Navigator.pop(context);
          } else if (state is DriveAttachSuccess) {
            Navigator.pop(context);
            Navigator.pop(context);
          }
        },
        builder: (context, state) => AppDialog(
          title: 'ATTACH DRIVE',
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
                    decoration: InputDecoration(labelText: 'Drive ID'),
                    validationMessages: (_) => kValidationMessages,
                  ),
                  const SizedBox(height: 16),
                  ReactiveTextField(
                    formControlName: 'name',
                    decoration: InputDecoration(
                      labelText: 'Name',
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
              child: Text('CANCEL'),
              onPressed: () => Navigator.of(context).pop(null),
            ),
            ElevatedButton(
              child: Text('ATTACH'),
              onPressed: () => context.read<DriveAttachCubit>().submit(),
            ),
          ],
        ),
      );
}

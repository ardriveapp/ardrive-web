import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

import 'components.dart';

Future<void> promptToAttachDrive(BuildContext context) => showDialog(
      context: context,
      builder: (BuildContext context) => DriveAttachForm(),
    );

class DriveAttachForm extends StatelessWidget {
  @override
  Widget build(BuildContext context) => BlocProvider<DriveAttachCubit>(
        create: (context) => DriveAttachCubit(
          arweave: context.read<ArweaveService>(),
          drivesDao: context.read<DrivesDao>(),
          syncBloc: context.read<SyncCubit>(),
          drivesBloc: context.read<DrivesCubit>(),
        ),
        child: BlocConsumer<DriveAttachCubit, DriveAttachState>(
          listener: (context, state) {
            if (state is DriveAttachInProgress) {
              showProgressDialog(context, 'ATTACHING DRIVE...');
            } else if (state is DriveAttachInitial) {
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
                      showErrors: (control) => control.dirty && control.invalid,
                      validationMessages: kValidationMessages,
                    ),
                    Container(height: 16),
                    ReactiveTextField(
                      formControlName: 'name',
                      decoration: InputDecoration(labelText: 'Name'),
                      showErrors: (control) => control.dirty && control.invalid,
                      validationMessages: kValidationMessages,
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
        ),
      );
}

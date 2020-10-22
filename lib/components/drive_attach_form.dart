import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

import 'components.dart';

class DriveAttachForm extends StatelessWidget {
  @override
  Widget build(BuildContext context) => BlocProvider<DriveAttachCubit>(
        create: (context) => DriveAttachCubit(
          arweave: context.repository<ArweaveService>(),
          drivesDao: context.repository<DrivesDao>(),
          syncBloc: context.bloc<SyncCubit>(),
          drivesBloc: context.bloc<DrivesCubit>(),
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
                formGroup: context.bloc<DriveAttachCubit>().form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ReactiveTextField(
                      formControlName: 'driveId',
                      autofocus: true,
                      decoration: InputDecoration(labelText: 'Drive ID'),
                      validationMessages: {
                        'drive-not-found': 'Could not find specified drive.',
                      },
                    ),
                    Container(height: 16),
                    ReactiveTextField(
                      formControlName: 'name',
                      decoration: InputDecoration(labelText: 'Name'),
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
                onPressed: () => context.bloc<DriveAttachCubit>().submit(),
              ),
            ],
          ),
        ),
      );
}

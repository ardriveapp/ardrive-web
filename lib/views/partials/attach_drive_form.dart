import 'package:drive/blocs/blocs.dart';
import 'package:drive/repositories/repositories.dart';
import 'package:drive/views/partials/progress_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AttachDriveForm extends StatefulWidget {
  @override
  _AttachDriveFormState createState() => _AttachDriveFormState();
}

class _AttachDriveFormState extends State<AttachDriveForm> {
  TextEditingController driveIdController;
  TextEditingController nameController;

  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    driveIdController = TextEditingController();
    nameController = TextEditingController();
  }

  @override
  Widget build(BuildContext context) => BlocProvider<DriveAttachBloc>(
        create: (context) => DriveAttachBloc(
          arweaveDao: context.repository<ArweaveDao>(),
          drivesDao: context.repository<DrivesDao>(),
          syncBloc: context.bloc<SyncBloc>(),
          drivesBloc: context.bloc<DrivesBloc>(),
          userBloc: context.bloc<UserBloc>(),
        ),
        child: BlocConsumer<DriveAttachBloc, DriveAttachState>(
          listener: (context, state) {
            if (state is DriveAttachInProgress) {
              showProgressDialog(context, 'Attaching drive...');
            } else if (state is DriveAttachSuccessful) {
              Navigator.pop(context);
              Navigator.pop(context);
            }
          },
          builder: (context, state) => AlertDialog(
            title: Text('Attach drive'),
            content: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    autofocus: true,
                    controller: driveIdController,
                    validator: (value) =>
                        value.isEmpty ? 'This field is required' : null,
                    decoration: InputDecoration(labelText: 'Drive ID'),
                  ),
                  Container(height: 16),
                  TextFormField(
                    controller: nameController,
                    validator: (value) =>
                        value.isEmpty ? 'This field is required' : null,
                    decoration: InputDecoration(labelText: 'Name'),
                  ),
                ],
              ),
            ),
            actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0),
            actions: [
              FlatButton(
                child: Text('CANCEL'),
                onPressed: () => Navigator.of(context).pop(null),
              ),
              FlatButton(
                child: Text('ATTACH'),
                onPressed: () {
                  if (_formKey.currentState.validate()) {
                    context.bloc<DriveAttachBloc>().add(AttemptDriveAttach(
                        driveIdController.text, nameController.text));
                  }
                },
              ),
            ],
          ),
        ),
      );
}

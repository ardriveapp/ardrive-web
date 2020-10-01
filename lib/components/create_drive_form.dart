import 'package:drive/blocs/blocs.dart';
import 'package:drive/entities/entities.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> promptToCreateDrive(BuildContext context) => showDialog(
      context: context,
      builder: (BuildContext context) => CreateDriveForm(),
    );

class CreateDriveForm extends StatefulWidget {
  final String initialName;

  const CreateDriveForm({this.initialName});

  @override
  _CreateDriveFormState createState() => _CreateDriveFormState();
}

class _CreateDriveFormState extends State<CreateDriveForm> {
  TextEditingController _nameController;
  String _drivePrivacy = DrivePrivacy.private;

  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Create drive'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                autofocus: true,
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                validator: (value) =>
                    value.isEmpty ? 'This field is required' : null,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              Container(height: 16),
              DropdownButtonFormField<String>(
                value: _drivePrivacy,
                onChanged: (newValue) =>
                    setState(() => _drivePrivacy = newValue),
                decoration: const InputDecoration(labelText: 'Privacy'),
                items: const [
                  DropdownMenuItem(
                    value: 'public',
                    child: Text('Public'),
                  ),
                  DropdownMenuItem(
                    value: 'private',
                    child: Text('Private'),
                  )
                ],
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0),
        actions: [
          FlatButton(
            child: Text('CANCEL'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          FlatButton(
            child: Text('CREATE'),
            onPressed: () {
              if (_formKey.currentState.validate()) {
                context
                    .bloc<DrivesBloc>()
                    .add(NewDrive(_nameController.text, _drivePrivacy));

                Navigator.of(context).pop();
              }
            },
          ),
        ],
      );
}

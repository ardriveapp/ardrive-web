import 'package:drive/blocs/blocs.dart';
import 'package:drive/entities/entities.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'text_field_dialog.dart';

Future<void> promptToCreateNewDrive(BuildContext context) async {
  final driveName = await showTextFieldDialog(
    context,
    title: 'New drive',
    fieldLabel: 'Drive name',
    confirmingActionLabel: 'CREATE',
  );

  if (driveName != null) {
    context.bloc<DrivesBloc>().add(NewDrive(driveName, DrivePrivacy.private));
  }
}

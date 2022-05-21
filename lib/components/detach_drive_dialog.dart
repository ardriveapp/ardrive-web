import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components.dart';

Future<void> showDetachDriveDialog({
  required BuildContext context,
  required DriveID driveID,
  required String driveName,
}) =>
    showDialog(
      context: context,
      builder: (BuildContext context) => AppDialog(
        title: appLocalizationsOf(context).detachDrive,
        content:
            Text(appLocalizationsOf(context).detachDriveQuestion(driveName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(appLocalizationsOf(context).cancelEmphasized),
          ),
          TextButton(
            onPressed: () {
              context.read<DriveDao>().detachDrive(driveID);
              context.read<DrivesCubit>().resetDriveSelection();
              Navigator.of(context).pop();
            },
            child: Text(appLocalizationsOf(context).confirmEmphasized),
          ),
        ],
      ),
    );

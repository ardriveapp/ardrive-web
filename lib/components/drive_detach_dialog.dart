import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> showDetachDriveDialog({
  required BuildContext context,
  required DriveID driveID,
  required String driveName,
}) =>
    showArDriveDialog(
      context,
      content: ArDriveStandardModalNew(
        title: appLocalizationsOf(context).detachDrive,
        description: appLocalizationsOf(context).detachDriveQuestion(driveName),
        actions: [
          ModalAction(
            action: () => Navigator.of(context).pop(null),
            title: appLocalizationsOf(context).cancelEmphasized,
          ),
          ModalAction(
            action: () {
              context.read<DrivesCubit>().detachDrive(driveID);
              Navigator.of(context).pop();
            },
            title: appLocalizationsOf(context).detachEmphasized,
          ),
        ],
      ),
    );

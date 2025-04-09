import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/shared/blocs/private_drive_migration/private_drive_migration_bloc.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

void showMigratePrivateDrivesModal(BuildContext context) {
  showArDriveDialog(
    context,
    content: BlocBuilder<DrivesCubit, DrivesState>(
      builder: (context, state) {
        if (state is! DrivesLoadSuccess) {
          return const SizedBox.shrink();
        }

        final privateDriveMigrationBloc =
            context.read<PrivateDriveMigrationBloc>();

        final drivesToMigrate = state.userDrives
            .where((drive) =>
                drive.privacy == DrivePrivacyTag.private &&
                (drive.signatureType == '1' || drive.signatureType == null) &&
                drive.driveKeyGenerated == true)
            .toList();

        if (drivesToMigrate.isEmpty) {
          Navigator.of(context).pop();
          return const SizedBox.shrink();
        }

        return ArDriveStandardModalNew(
          title: 'Migrate Private Drives',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The following private drives need to be migrated:',
              ),
              const SizedBox(height: 16),
              ...drivesToMigrate.map((drive) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      drive.name,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )),
            ],
          ),
          actions: [
            ModalAction(
              action: () => Navigator.of(context).pop(),
              title: 'Close',
            ),
            ModalAction(
              action: () {
                // TODO: Implement migration logic
                // Navigator.of(context).pop();
                privateDriveMigrationBloc
                    .add(const PrivateDriveMigrationStartEvent());
              },
              title: 'Migrate',
            ),
          ],
        );
      },
    ),
  );
}

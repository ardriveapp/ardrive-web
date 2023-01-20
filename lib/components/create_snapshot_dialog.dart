import 'package:ardrive/blocs/create_snapshot/create_snapshot_cubit.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/user_interaction_wrapper.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/pst/pst.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> promptToCreateSnapshot(
  BuildContext context,
  Drive drive,
) async {
  final arweave = context.read<ArweaveService>();
  final pst = context.read<PstService>();

  final driveId = drive.id;
  final currentHeight = await arweave.getCurrentBlockHeight();
  final range = Range(start: 0, end: currentHeight);

  print('Create snapshot for drive $driveId at $range');

  // ignore: use_build_context_synchronously
  return showModalDialog(
      context,
      () => showDialog(
            context: context,
            builder: (context) {
              return BlocProvider(
                create: (_) => CreateSnapshotCubit(
                  arweave: arweave,
                  driveDao: context.read<DriveDao>(),
                  profileCubit: context.read<ProfileCubit>(),
                  pst: pst,
                )..selectDriveAndHeightRange(
                    driveId,
                    range,
                    currentHeight,
                  ),
                child: CreateSnapshotDialog(
                  arweave: arweave,
                  drive: drive,
                ),
              );
            },
          ));
}

class CreateSnapshotDialog extends StatelessWidget {
  final Drive drive;
  final ArweaveService _arweave;

  const CreateSnapshotDialog({super.key, required this.drive, required arweave})
      : _arweave = arweave;

  @override
  Widget build(BuildContext context) {
    final createSnapshotCubit = context.read<CreateSnapshotCubit>();

    return BlocBuilder<CreateSnapshotCubit, CreateSnapshotState>(
      builder: (context, snapshotCubitState) {
        return AppDialog(
          title: appLocalizationsOf(context).createSnapshot,
          content: SizedBox(
              width: kMediumDialogWidth,
              child: Row(
                children: [
                  if (snapshotCubitState is ComputingSnapshotData ||
                      snapshotCubitState is UploadingSnapshot)
                    const Padding(
                      padding: EdgeInsets.only(right: 16.0),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  if (snapshotCubitState is ConfirmingSnapshotCreation) ...{
                    Text(
                      appLocalizationsOf(context)
                          .createSnapshotExplanation(drive.name),
                    ),

                    /// display cost of snapshot creation, already present in the state
                  }
                ],
              )),
          actions: <Widget>[
            if (snapshotCubitState is ConfirmingSnapshotCreation) ...{
              TextButton(
                child: Text(appLocalizationsOf(context).cancel),
                onPressed: () {
                  print('Cancel snapshot creation');
                  Navigator.of(context).pop();
                },
              ),
              ElevatedButton(
                onPressed: () async => {
                  print('Confirm snapshot creation'),
                  await createSnapshotCubit.confirmSnapshotCreation(),
                  Navigator.of(context).pop(),
                },
                child: Text(appLocalizationsOf(context).confirmEmphasized),
              ),
            }
          ],
        );
      },
    );
  }
}

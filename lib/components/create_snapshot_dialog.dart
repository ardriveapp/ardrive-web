import 'package:ardrive/blocs/create_snapshot/create_snapshot_cubit.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/user_interaction_wrapper.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/pst/pst.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/split_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> promptToCreateSnapshot(
  BuildContext context,
  Drive drive,
) async {
  // ignore: use_build_context_synchronously
  return showModalDialog(
      context,
      () => showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) {
              return BlocProvider(
                create: (_) => CreateSnapshotCubit(
                  arweave: context.read<ArweaveService>(),
                  driveDao: context.read<DriveDao>(),
                  profileCubit: context.read<ProfileCubit>(),
                  pst: context.read<PstService>(),
                ),
                child: CreateSnapshotDialog(
                  drive: drive,
                ),
              );
            },
          ));
}

class CreateSnapshotDialog extends StatelessWidget {
  final Drive drive;

  const CreateSnapshotDialog({super.key, required this.drive});

  @override
  Widget build(BuildContext context) {
    final createSnapshotCubit = context.read<CreateSnapshotCubit>();

    return BlocBuilder<CreateSnapshotCubit, CreateSnapshotState>(
      builder: (context, snapshotCubitState) {
        if (snapshotCubitState is CreateSnapshotInitial) {
          return _explanationDialog(context, drive);
        } else if (snapshotCubitState is ComputingSnapshotData ||
            snapshotCubitState is UploadingSnapshot) {
          return _loadingDialog(context, snapshotCubitState);
        } else if (snapshotCubitState is SnapshotUploadSuccess) {
          return _successDialog(context, drive.name);
        } else if (snapshotCubitState is SnapshotUploadFailure ||
            snapshotCubitState is ComputeSnapshotDataFailure) {
          return _failureDialog(context, drive.id);
        } else if (snapshotCubitState is CreateSnapshotInsufficientBalance) {
          return _insufficientBalanceDialog(context, snapshotCubitState);
        } else {
          return _confirmDialog(
            context,
            drive,
            createSnapshotCubit,
            snapshotCubitState,
          );
        }
      },
    );
  }
}

Widget _explanationDialog(BuildContext context, Drive drive) {
  final createSnapshotCubit = context.read<CreateSnapshotCubit>();

  return AppDialog(
    title: appLocalizationsOf(context).createSnapshot,
    dismissable: true,
    content: SizedBox(
      width: kMediumDialogWidth,
      child: Row(
        children: [
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: splitTranslationsWithMultipleStyles(
                      originalText: appLocalizationsOf(context)
                          .createSnapshotExplanation(drive.name),
                      defaultMapper: (t) => TextSpan(
                        text: t,
                        style: Theme.of(context).textTheme.bodyText1,
                      ),
                      parts: {
                        drive.name: (t) => TextSpan(
                              text: t,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyText1!
                                  .copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                      },
                    ),
                  ),
                  style: Theme.of(context).textTheme.bodyText1,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        child: Text(appLocalizationsOf(context).cancelEmphasized),
        onPressed: () {
          Navigator.of(context).pop();
        },
      ),
      TextButton(
        child: Text(appLocalizationsOf(context).proceedCongestionEmphasized),
        onPressed: () {
          createSnapshotCubit.confirmDriveAndHeighRange(drive.id);
        },
      ),
    ],
  );
}

Widget _loadingDialog(
  BuildContext context,
  CreateSnapshotState snapshotCubitState,
) {
  final createSnapshotCubit = context.read<CreateSnapshotCubit>();
  final onDismiss = snapshotCubitState is ComputingSnapshotData
      ? () {
          Navigator.of(context).pop();
          createSnapshotCubit.cancelSnapshotCreation();
        }
      : null;

  return ProgressDialog(
    title: snapshotCubitState is ComputingSnapshotData
        ? appLocalizationsOf(context).determiningSizeAndCostOfSnapshot
        : appLocalizationsOf(context).uploadingSnapshot,
    progressDescription: Center(
      child: snapshotCubitState is ComputingSnapshotData
          ? Text(appLocalizationsOf(context).thisMayTakeAWhile)
          : null,
    ),
    actions: [
      if (onDismiss != null)
        TextButton(
          onPressed: onDismiss,
          child: Text(
            appLocalizationsOf(context).cancelEmphasized,
          ),
        ),
    ],
  );
}

Widget _successDialog(BuildContext context, String driveName) {
  return AppDialog(
    title: appLocalizationsOf(context).snapshotSuceeded,
    content: SizedBox(
      width: kMediumDialogWidth,
      child: Row(
        children: [
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: appLocalizationsOf(context)
                        .snapshotCreationSucceeded(driveName),
                  ),
                  style: Theme.of(context).textTheme.bodyText1,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        child: Text(appLocalizationsOf(context).ok),
        onPressed: () {
          Navigator.of(context).pop();
        },
      ),
    ],
  );
}

Widget _failureDialog(
  BuildContext context,
  DriveID driveId,
) {
  final createSnapshotCubit = context.read<CreateSnapshotCubit>();

  return AppDialog(
    title: appLocalizationsOf(context).snapshotFailed,
    content: SizedBox(
      width: kMediumDialogWidth,
      child: Row(
        children: [
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: appLocalizationsOf(context).snapshotCreationFailed,
                  ),
                  style: Theme.of(context).textTheme.bodyText1,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      ElevatedButton(
        onPressed: () {
          createSnapshotCubit.confirmDriveAndHeighRange(driveId);
        },
        child: Text(
          appLocalizationsOf(context).tryAgainEmphasized,
        ),
      ),
      TextButton(
        child: Text(appLocalizationsOf(context).ok),
        onPressed: () {
          Navigator.of(context).pop();
        },
      ),
    ],
  );
}

Widget _insufficientBalanceDialog(
  BuildContext context,
  CreateSnapshotInsufficientBalance snapshotCubitState,
) {
  return AppDialog(
    title: appLocalizationsOf(context).insufficientARForUpload,
    content: SizedBox(
      width: kMediumDialogWidth,
      child: Row(
        children: [
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: appLocalizationsOf(context)
                        .insufficientBalanceForSnapshot(
                      snapshotCubitState.walletBalance,
                      snapshotCubitState.arCost,
                    ),
                  ),
                  style: Theme.of(context).textTheme.bodyText1,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        child: Text(appLocalizationsOf(context).ok),
        onPressed: () {
          Navigator.of(context).pop();
        },
      ),
    ],
  );
}

Widget _confirmDialog(
  BuildContext context,
  Drive drive,
  CreateSnapshotCubit createSnapshotCubit,
  CreateSnapshotState snapshotCubitState,
) {
  return AppDialog(
    title: appLocalizationsOf(context).createSnapshot,
    content: SizedBox(
        width: kMediumDialogWidth,
        child: Row(
          children: [
            if (snapshotCubitState is ConfirmingSnapshotCreation) ...{
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: splitTranslationsWithMultipleStyles(
                          originalText: appLocalizationsOf(context)
                              .snapshotOfDrive(drive.name),
                          defaultMapper: (t) => TextSpan(
                            text: t,
                            style: Theme.of(context).textTheme.bodyText1,
                          ),
                          parts: {
                            drive.name: (t) => TextSpan(
                                  text: t,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyText1!
                                      .copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                          },
                        ),
                      ),
                      style: Theme.of(context).textTheme.bodyText1,
                    ),
                    const Divider(),
                    const SizedBox(height: 16),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: appLocalizationsOf(context).cost(
                              snapshotCubitState.arUploadCost,
                            ),
                          ),
                          if (snapshotCubitState.usdUploadCost != null)
                            TextSpan(
                              text: snapshotCubitState.usdUploadCost! >= 0.01
                                  ? ' (~${snapshotCubitState.usdUploadCost!.toStringAsFixed(2)} USD)'
                                  : ' (< 0.01 USD)',
                            ),
                        ],
                        style: Theme.of(context).textTheme.bodyText1,
                      ),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: appLocalizationsOf(context).snapshotSize(
                              filesize(snapshotCubitState.snapshotSize),
                            ),
                          ),
                        ],
                        style: Theme.of(context).textTheme.bodyText1,
                      ),
                    ),
                  ],
                ),
              ),

              // TODO: PE-2933
            }
          ],
        )),
    actions: <Widget>[
      if (snapshotCubitState is ConfirmingSnapshotCreation) ...{
        TextButton(
          child: Text(appLocalizationsOf(context).cancelEmphasized),
          onPressed: () {
            print('Cancel snapshot creation');
            Navigator.of(context).pop();
          },
        ),
        ElevatedButton(
          onPressed: () async => {
            print('Confirm snapshot creation'),
            await createSnapshotCubit.confirmSnapshotCreation(),
          },
          child: Text(appLocalizationsOf(context).uploadEmphasized),
        ),
      }
    ],
  );
}

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
) {
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
      builder: (context, state) {
        if (state is CreateSnapshotInitial) {
          return _explanationDialog(context, drive);
        } else if (state is ComputingSnapshotData ||
            state is UploadingSnapshot ||
            state is PreparingAndSigningTransaction) {
          return _loadingDialog(context, state);
        } else if (state is SnapshotUploadSuccess) {
          return _successDialog(context, drive.name);
        } else if (state is SnapshotUploadFailure ||
            state is ComputeSnapshotDataFailure) {
          return _failureDialog(context, drive.id);
        } else if (state is CreateSnapshotInsufficientBalance) {
          return _insufficientBalanceDialog(context, state);
        } else {
          return _confirmDialog(
            context,
            drive,
            createSnapshotCubit,
            state,
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
  CreateSnapshotState state,
) {
  bool isArConnectProfile = state is PreparingAndSigningTransaction
      ? state.isArConnectProfile
      : false;

  final createSnapshotCubit = context.read<CreateSnapshotCubit>();
  final onDismiss = state is ComputingSnapshotData
      ? () {
          Navigator.of(context).pop();
          createSnapshotCubit.cancelSnapshotCreation();
        }
      : null;

  final String title = state is ComputingSnapshotData
      ? appLocalizationsOf(context).determiningSizeAndCostOfSnapshot
      : state is PreparingAndSigningTransaction
          ? (isArConnectProfile
              ? appLocalizationsOf(context).finishingThingsUp
              : appLocalizationsOf(context).determiningSizeAndCostOfSnapshot)
          : appLocalizationsOf(context).uploadingSnapshot;

  final String description = state is ComputingSnapshotData
      ? appLocalizationsOf(context).thisMayTakeAWhile
      : state is PreparingAndSigningTransaction && isArConnectProfile
          ? appLocalizationsOf(context).pleaseRemainOnThisTabSnapshots
          : appLocalizationsOf(context).thisMayTakeAWhile;

  return ProgressDialog(
    title: title,
    progressDescription: Center(
      child: Text(description),
    ),
    actions: [
      if (onDismiss != null) ...{
        TextButton(
          onPressed: onDismiss,
          child: Text(
            appLocalizationsOf(context).cancelEmphasized,
          ),
        ),
      } else if (state is PreparingAndSigningTransaction &&
          !isArConnectProfile) ...{
        SizedBox(
          height: Theme.of(context).buttonTheme.height,
        ),
      }
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
  CreateSnapshotInsufficientBalance state,
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
                      state.walletBalance,
                      state.arCost,
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
  CreateSnapshotState state,
) {
  return AppDialog(
    title: appLocalizationsOf(context).createSnapshot,
    content: SizedBox(
        width: kMediumDialogWidth,
        child: Row(
          children: [
            if (state is ConfirmingSnapshotCreation) ...{
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
                              state.arUploadCost,
                            ),
                          ),
                          if (state.usdUploadCost != null)
                            TextSpan(
                              text: state.usdUploadCost! >= 0.01
                                  ? ' (~${state.usdUploadCost!.toStringAsFixed(2)} USD)'
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
                              filesize(state.snapshotSize),
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
      if (state is ConfirmingSnapshotCreation) ...{
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

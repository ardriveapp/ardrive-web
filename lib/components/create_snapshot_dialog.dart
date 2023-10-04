import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/create_snapshot/create_snapshot_cubit.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/components/payment_method_selector_widget.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/user_interaction_wrapper.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/services/pst/pst.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/html/html_util.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive/utils/split_localizations.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> promptToCreateSnapshot(
  BuildContext context,
  Drive drive,
) async {
  return showModalDialog(
      context,
      () => showAnimatedDialog(
            context,
            barrierDismissible: false,
            content: BlocProvider(
              create: (_) => CreateSnapshotCubit(
                arweave: context.read<ArweaveService>(),
                driveDao: context.read<DriveDao>(),
                profileCubit: context.read<ProfileCubit>(),
                pst: context.read<PstService>(),
                tabVisibility: TabVisibilitySingleton(),
                auth: context.read<ArDriveAuth>(),
                paymentService: context.read<PaymentService>(),
                turboBalanceRetriever: TurboBalanceRetriever(
                  paymentService: context.read<PaymentService>(),
                ),
                configService: context.read<ConfigService>(),
                turboService: context.read<TurboUploadService>(),
              ),
              child: CreateSnapshotDialog(
                drive: drive,
              ),
            ),
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

  return ArDriveStandardModal(
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
                        style: ArDriveTypography.body.buttonNormalRegular(),
                      ),
                      parts: {
                        drive.name: (t) => TextSpan(
                              text: t,
                              style: ArDriveTypography.body
                                  .buttonNormalBold()
                                  .copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                      },
                    ),
                  ),
                  style: ArDriveTypography.body.buttonNormalRegular(),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      ModalAction(
        title: appLocalizationsOf(context).cancelEmphasized,
        action: () {
          Navigator.of(context).pop();
        },
      ),
      ModalAction(
        title: appLocalizationsOf(context).proceedEmphasized,
        action: () {
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

  return ProgressDialog(
    title: _loadingDialogTitle(context, state),
    progressDescription: Center(
      child: Text(
        _loadingDialogDescription(context, state, isArConnectProfile),
        style: ArDriveTypography.body.buttonNormalRegular(),
      ),
    ),
    actions: [
      if (onDismiss != null)
        ModalAction(
          action: onDismiss,
          title: appLocalizationsOf(context).cancelEmphasized,
        )
    ],
  );
}

String _loadingDialogTitle(BuildContext context, CreateSnapshotState state) {
  if (state is ComputingSnapshotData) {
    return appLocalizationsOf(context).determiningSizeAndCostOfSnapshot;
  } else if (state is PreparingAndSigningTransaction) {
    return appLocalizationsOf(context).finishingThingsUp;
  } else {
    return appLocalizationsOf(context).uploadingSnapshot;
  }
}

String _loadingDialogDescription(
  BuildContext context,
  CreateSnapshotState state,
  bool isArConnectProfile,
) {
  if (state is ComputingSnapshotData) {
    return appLocalizationsOf(context).thisMayTakeAWhile;
  } else if (state is PreparingAndSigningTransaction) {
    if (isArConnectProfile) {
      return appLocalizationsOf(context).pleaseRemainOnThisTabSnapshots;
    } else {
      return appLocalizationsOf(context).thisMayTakeAWhile;
    }
  } else {
    // Description for uploading snapshot
    return '';
  }
}

Widget _successDialog(BuildContext context, String driveName) {
  return ArDriveStandardModal(
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
                  style: ArDriveTypography.body.buttonNormalRegular(),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      ModalAction(
        title: appLocalizationsOf(context).ok,
        action: () {
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

  return ArDriveStandardModal(
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
                  style: ArDriveTypography.body.buttonNormalRegular(),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      ModalAction(
        action: () {
          createSnapshotCubit.confirmDriveAndHeighRange(driveId);
        },
        title: appLocalizationsOf(context).tryAgainEmphasized,
      ),
      ModalAction(
        title: appLocalizationsOf(context).ok,
        action: () {
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
  return ArDriveStandardModal(
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
                  style: ArDriveTypography.body.buttonNormalRegular(),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      ModalAction(
        title: appLocalizationsOf(context).ok,
        action: () {
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
  return ArDriveStandardModal(
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
                            style: ArDriveTypography.body.buttonNormalRegular(),
                          ),
                          parts: {
                            drive.name: (t) => TextSpan(
                                  text: t,
                                  style: ArDriveTypography.body
                                      .buttonNormalBold()
                                      .copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                          },
                        ),
                      ),
                      style: ArDriveTypography.body.buttonNormalRegular(),
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
                        style: ArDriveTypography.body.buttonNormalRegular(),
                      ),
                    ),
                    const Divider(),
                    const SizedBox(height: 16),
                    if (state.isFreeThanksToTurbo) ...{
                      Text(
                        appLocalizationsOf(context).freeTurboTransaction,
                        style: ArDriveTypography.body.buttonNormalRegular(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeFgDefault,
                        ),
                      ),
                    } else ...{
                      PaymentMethodSelector(
                        uploadMethod: state.uploadMethod,
                        costEstimateTurbo: state.costEstimateTurbo,
                        costEstimateAr: state.costEstimateAr,
                        hasNoTurboBalance: state.hasNoTurboBalance,
                        isTurboUploadPossible: true,
                        arBalance: state.arBalance,
                        sufficientArBalance: state.sufficientBalanceToPayWithAr,
                        turboCredits: state.turboCredits,
                        sufficentCreditsBalance:
                            state.sufficientBalanceToPayWithTurbo,
                        isFreeThanksToTurbo: false,
                        onTurboTopupSucess: () {
                          createSnapshotCubit.refreshTurboBalance();
                        },
                        onArSelect: () {
                          createSnapshotCubit.setUploadMethod(UploadMethod.ar);
                        },
                        onTurboSelect: () {
                          createSnapshotCubit
                              .setUploadMethod(UploadMethod.turbo);
                        },
                      ),
                    }
                  ],
                ),
              ),

              // TODO: PE-2933
            }
          ],
        )),
    actions: [
      if (state is ConfirmingSnapshotCreation) ...{
        ModalAction(
          title: appLocalizationsOf(context).cancelEmphasized,
          action: () {
            logger.i('Cancel snapshot creation');
            Navigator.of(context).pop();
          },
        ),
        ModalAction(
          action: () async => {
            logger.i('Confirm snapshot creation'),
            await createSnapshotCubit.confirmSnapshotCreation(),
          },
          title: appLocalizationsOf(context).uploadEmphasized,
          isEnable: state.isButtonToUploadEnabled,
        ),
      }
    ],
  );
}

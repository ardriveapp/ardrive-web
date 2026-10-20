import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive/components/turbo_free_status_message.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/components/turbo_payment_required_dialog.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/create_snapshot/create_snapshot_cubit.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_bloc.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_event.dart';
import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/components/payment_method_selector_widget.dart';
import 'package:ardrive/drive_state/presentation/drive_state_creation_modal.dart';
import 'package:ardrive/drive_state/presentation/drive_state_publish_offer.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/split_localizations.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pst/pst.dart';

/// Whether "Create snapshot" makes a drive state artifact for [drive] rather
/// than the older kind of snapshot.
///
/// Users see one word for both. Wherever publishing an artifact is offered for
/// this drive ([driveStatePublishOffer]: the flag, ownership, write access and
/// a drive with something in it), a snapshot is an artifact. Anywhere else it
/// is the older snapshot, as before.
///
/// Every condition is read from [drive] itself, never from the drive or folder
/// on screen. "Create snapshot" is offered from the list of drives, where no
/// drive is open, and from inside a drive, where the folder in view can be an
/// empty subfolder of a full one. Reading `DriveDetailCubit` answered for the
/// wrong thing in both: the list always got the older snapshot, and so did an
/// empty subfolder.
Future<bool> createsDriveStateSnapshot(BuildContext context, Drive drive) {
  final ConfigService configService;
  final ProfileState profile;
  final DriveDao driveDao;
  try {
    configService = context.read<ConfigService>();
    profile = context.read<ProfileCubit>().state;
    driveDao = context.read<DriveDao>();
  } on ProviderNotFoundException {
    return Future.value(false);
  }

  return drivePublishesStateSnapshot(
    drive: drive,
    publishingEnabled: configService.config.enableDriveStatePublishing,
    walletAddress:
        profile is ProfileLoggedIn ? profile.user.walletAddress : null,
    driveDao: driveDao,
  );
}

/// [createsDriveStateSnapshot] without a [BuildContext].
///
/// [walletAddress] is the logged-in wallet, or null when nobody is logged in.
Future<bool> drivePublishesStateSnapshot({
  required Drive drive,
  required bool publishingEnabled,
  required String? walletAddress,
  required DriveDao driveDao,
}) async {
  final isDriveOwner =
      walletAddress != null && drive.ownerAddress == walletAddress;

  // Nothing the database says can make an offer of these, so it isn't asked.
  if (!publishingEnabled || !isDriveOwner) {
    return false;
  }

  final hasEntries = await driveDao.driveHasEntries(
    driveId: drive.id,
    rootFolderId: drive.rootFolderId,
  );

  return driveStatePublishOffer(
        publishingEnabled: publishingEnabled,
        isDriveOwner: isDriveOwner,
        // `DriveDetailCubit` grants write access to a logged-in wallet that
        // owns the drive, and to nobody else.
        hasWritePermissions: isDriveOwner,
        driveIsEmpty: !hasEntries,
      ) ==
      DriveStatePublishOffer.offered;
}

/// Opens whichever snapshot [drive] gets - see [createsDriveStateSnapshot].
Future<void> promptToCreateSnapshot(
  BuildContext context,
  Drive drive,
) async {
  final createsDriveState = await createsDriveStateSnapshot(context, drive);
  if (!context.mounted) {
    return;
  }

  if (createsDriveState) {
    return promptToCreateDriveState(context, drive: drive);
  }

  final PromptToSnapshotBloc promptToSnapshotBloc =
      context.read<PromptToSnapshotBloc>();
  promptToSnapshotBloc.add(DriveSnapshotting(driveId: drive.id));
  return showAnimatedDialog(
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
        promptToSnapshotBloc: promptToSnapshotBloc,
      ),
    ),
  ).then((_) {
    promptToSnapshotBloc.add(const SelectedDrive(driveId: null));
  });
}

class CreateSnapshotDialog extends StatelessWidget {
  final Drive drive;
  final PromptToSnapshotBloc promptToSnapshotBloc;

  const CreateSnapshotDialog({
    super.key,
    required this.drive,
    required this.promptToSnapshotBloc,
  });

  @override
  Widget build(BuildContext context) {
    final createSnapshotCubit = context.read<CreateSnapshotCubit>();

    return BlocConsumer<CreateSnapshotCubit, CreateSnapshotState>(
      listener: (context, state) {
        if (state is SnapshotUploadSuccess) {
          promptToSnapshotBloc.add(
            DriveSnapshotted(
              driveId: drive.id,
              // TODO
              /// txsSyncedWithGqlCount: state.notSnapshottedTxsCount,
            ),
          );
        } else if (state is SnapshotUploadFailure && state.isPaymentError) {
          // This dialog is shown with barrierDismissible: false, so it has to
          // be popped first — otherwise dismissing the payment dialog leaves
          // an invisible, undismissable barrier over the app.
          Navigator.of(context).pop();
          showTurboPaymentRequiredDialog(context);
        }
      },
      builder: (context, state) {
        if (state is CreateSnapshotInitial) {
          return _explanationDialog(context, drive);
        } else if (state is ComputingSnapshotData ||
            state is UploadingSnapshot ||
            state is PreparingAndSigningTransaction) {
          return _loadingDialog(context, state);
        } else if (state is SnapshotUploadSuccess) {
          return _successDialog(context, drive.name);
        } else if (state is SnapshotUploadFailure && state.isPaymentError) {
          // Pop + payment dialog handled in the listener; render nothing for
          // any frame between the state landing and the pop taking effect.
          return const SizedBox.shrink();
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
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

  return ArDriveStandardModalNew(
    title: appLocalizationsOf(context).newSnapshot,
    content: Column(
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
                style: typography.paragraphNormal(
                  color: colorTokens.textMid,
                ),
              ),
              parts: {
                drive.name: (t) => TextSpan(
                      text: t,
                      style: typography.paragraphNormal(
                        fontWeight: ArFontWeight.semiBold,
                        color: colorTokens.textHigh,
                      ),
                    ),
              },
            ),
          ),
          style: typography.paragraphNormal(
            color: colorTokens.textMid,
          ),
        ),
      ],
    ),
    actions: [
      ModalAction(
        title: appLocalizationsOf(context).cancelEmphasized,
        action: () {
          Navigator.of(context).pop();
        },
      ),
      ModalAction(
        title: appLocalizationsOf(context).createSnapshot,
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
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
  final onDismiss = state is ComputingSnapshotData
      ? () {
          Navigator.of(context).pop();
          createSnapshotCubit.cancelSnapshotCreation();
        }
      : null;

  return ProgressDialog(
    useNewArDriveUI: true,
    title: _loadingDialogTitle(context, state),
    progressDescription: Center(
      child: Text(
        _loadingDialogDescription(context, state, isArConnectProfile),
        style: typography.paragraphNormal(
          color: colorTokens.textMid,
        ),
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
    if (state.totalTransactions > 0) {
      return appLocalizationsOf(context).snapshotProcessingProgress(
        state.processedTransactions,
        state.totalTransactions,
      );
    }
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
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

  return ArDriveStandardModalNew(
    title: appLocalizationsOf(context).snapshotSuceeded,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: appLocalizationsOf(context)
                .snapshotCreationSucceeded(driveName),
          ),
          style: typography.paragraphNormal(
            color: colorTokens.textMid,
          ),
        ),
      ],
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
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

  return ArDriveStandardModalNew(
    title: appLocalizationsOf(context).snapshotFailed,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: appLocalizationsOf(context).snapshotCreationFailed,
          ),
          style: typography.paragraphNormal(
            color: colorTokens.textMid,
          ),
        ),
      ],
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
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

  return ArDriveStandardModalNew(
    title: appLocalizationsOf(context).insufficientARForUpload,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: appLocalizationsOf(context).insufficientBalanceForSnapshot(
              state.walletBalance,
              state.arCost,
            ),
          ),
          style: typography.paragraphNormal(
            color: colorTokens.textMid,
          ),
        ),
      ],
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
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

  return ArDriveStandardModalNew(
    title: appLocalizationsOf(context).newSnapshot,
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
                            style: typography.paragraphNormal(
                              color: colorTokens.textMid,
                            ),
                          ),
                          parts: {
                            drive.name: (t) => TextSpan(
                                  text: t,
                                  style: typography.paragraphNormal(
                                    fontWeight: ArFontWeight.semiBold,
                                    color: colorTokens.textHigh,
                                  ),
                                ),
                          },
                        ),
                      ),
                      style: typography.paragraphNormal(
                        color: colorTokens.textMid,
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
                        style: typography.paragraphNormal(
                          color: colorTokens.textMid,
                        ),
                      ),
                    ),
                    const Divider(),
                    const SizedBox(height: 16),
                    TurboFreeStatusMessage(
                      status: state.freeStatus,
                      padding: const EdgeInsets.only(bottom: 12),
                    ),
                    if (!state.isFreeThanksToTurbo) ...{
                      PaymentMethodSelector(
                        uploadMethodInfo: UploadPaymentMethodInfo(
                          uploadMethod: state.uploadMethod,
                          totalSize: state.snapshotSize,
                          costEstimateTurbo: state.costEstimateTurbo,
                          costEstimateAr: state.costEstimateAr,
                          hasNoTurboBalance: state.hasNoTurboBalance,
                          isTurboUploadPossible: true,
                          arBalance: state.arBalance,
                          sufficientArBalance:
                              state.sufficientBalanceToPayWithAr,
                          turboCredits: state.turboCredits,
                          sufficentCreditsBalance:
                              state.sufficientBalanceToPayWithTurbo,
                          freeStatus: FreeUploadStatus.notEligible,
                        ),
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
            logger.i('Canceling snapshot creation');
            Navigator.of(context).pop();
          },
        ),
        ModalAction(
          action: () async => {
            logger.i('Confirming snapshot creation'),
            await createSnapshotCubit.confirmSnapshotCreation(),
          },
          title: appLocalizationsOf(context).uploadSnapshot,
          isEnable: state.isButtonToUploadEnabled,
        ),
      }
    ],
  );
}

import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/components/charged_review_dialog.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/turbo/topup/views/topup_modal.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/create_snapshot/create_snapshot_cubit.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_bloc.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_event.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/drive_state/presentation/drive_state_creation_modal.dart';
import 'package:ardrive/drive_state/presentation/drive_state_publish_offer.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
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
  return showArDriveDialog(
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

class CreateSnapshotDialog extends StatefulWidget {
  final Drive drive;
  final PromptToSnapshotBloc promptToSnapshotBloc;

  const CreateSnapshotDialog({
    super.key,
    required this.drive,
    required this.promptToSnapshotBloc,
  });

  @override
  State<CreateSnapshotDialog> createState() => _CreateSnapshotDialogState();
}

class _CreateSnapshotDialogState extends State<CreateSnapshotDialog> {
  Drive get drive => widget.drive;

  /// Whether Create snapshot or Try again has been pressed and has not come
  /// back. Set before the call: the cubit's busy state arrives only after it
  /// has checked the wallet, and a fast second press would pay twice.
  bool _submitting = false;

  Future<void> _run(Future<void> Function() step) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await step();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    // Opening the dialog is the ask: it starts working out the size and the
    // cost at once, so the first thing to read is the one screen that
    // creates the snapshot, not a screen that only explains it.
    final cubit = context.read<CreateSnapshotCubit>();
    if (cubit.state is CreateSnapshotInitial) {
      cubit.confirmDriveAndHeighRange(drive.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final createSnapshotCubit = context.read<CreateSnapshotCubit>();

    return BlocConsumer<CreateSnapshotCubit, CreateSnapshotState>(
      listener: (context, state) {
        if (state is SnapshotUploadSuccess) {
          widget.promptToSnapshotBloc.add(
            DriveSnapshotted(
              driveId: drive.id,
              // TODO
              /// txsSyncedWithGqlCount: state.notSnapshottedTxsCount,
            ),
          );
        }
      },
      builder: (context, state) {
        if (state is SnapshotUploadSuccess) {
          return _successDialog(context, drive.name);
        } else if (state is SnapshotUploadFailure ||
            state is ComputeSnapshotDataFailure) {
          // A payment the Turbo account can't make is told in this dialog,
          // with the way on, like any other failure.
          return _failureDialog(
            context,
            drive.id,
            busy: _submitting,
            run: _run,
            isPaymentError:
                state is SnapshotUploadFailure && state.isPaymentError,
          );
        } else if (state is ConfirmingSnapshotCreation) {
          return _confirmDialog(
            context,
            drive,
            createSnapshotCubit,
            state,
            busy: _submitting,
            run: _run,
          );
        }

        // Initial, computing, signing and uploading: the work, in this
        // dialog.
        return _loadingDialog(context, state);
      },
    );
  }
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
  // Until the upload starts, the work can be stopped: it has paid nothing.
  final onDismiss =
      state is ComputingSnapshotData || state is CreateSnapshotInitial
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
        style: typography.paragraphNormal(
          color: colorTokens.textMid,
        ),
      ),
    ),
    actions: [
      if (onDismiss != null)
        ModalAction.dismiss(
          action: onDismiss,
          title: appLocalizationsOf(context).cancelEmphasized,
        )
    ],
  );
}

String _loadingDialogTitle(BuildContext context, CreateSnapshotState state) {
  if (state is ComputingSnapshotData || state is CreateSnapshotInitial) {
    return appLocalizationsOf(context).snapshotPreparing;
  } else if (state is PreparingAndSigningTransaction) {
    return appLocalizationsOf(context).snapshotFinishing;
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
    return appLocalizationsOf(context).snapshotMayTakeAWhile;
  } else if (state is PreparingAndSigningTransaction) {
    if (isArConnectProfile) {
      return appLocalizationsOf(context).pleaseRemainOnThisTabSnapshots;
    } else {
      return appLocalizationsOf(context).snapshotMayTakeAWhile;
    }
  } else {
    // Description for the start and for uploading the snapshot
    return '';
  }
}

Widget _successDialog(BuildContext context, String driveName) {
  final l10n = appLocalizationsOf(context);

  return ArDriveStandardModalNew(
    title: l10n.snapshotSuceeded,
    description: l10n.snapshotCreationSucceeded(driveName),
    actions: [
      ModalAction.close(
        title: l10n.close,
        action: () {
          Navigator.of(context).pop();
        },
      ),
    ],
  );
}

Widget _failureDialog(
  BuildContext context,
  DriveID driveId, {
  required bool busy,
  required Future<void> Function(Future<void> Function()) run,
  bool isPaymentError = false,
}) {
  final createSnapshotCubit = context.read<CreateSnapshotCubit>();
  final l10n = appLocalizationsOf(context);

  return ArDriveStandardModalNew(
    title: isPaymentError ? l10n.freeAllowanceUsedUpTitle : l10n.snapshotFailed,
    content: ArDriveNotice(
      type: ArDriveNoticeType.error,
      message: isPaymentError
          ? l10n.freeAllowanceUsedUpDescription
          : l10n.snapshotCreationFailed,
    ),
    actions: [
      ModalAction.close(
        title: l10n.close,
        isEnable: !busy,
        action: () {
          Navigator.of(context).pop();
        },
      ),
      if (isPaymentError)
        ModalAction(
          title: l10n.buyCredits,
          action: () {
            Navigator.of(context).pop();
            showTurboTopupModal(context);
          },
        )
      else
        ModalAction(
          isLoading: busy,
          action: () => run(
            () => createSnapshotCubit.confirmDriveAndHeighRange(driveId),
          ),
          title: l10n.tryAgainEmphasized,
        ),
    ],
  );
}

/// What a snapshot is, how big it is and what it costs, with the one button
/// that creates it.
Widget _confirmDialog(
  BuildContext context,
  Drive drive,
  CreateSnapshotCubit createSnapshotCubit,
  ConfirmingSnapshotCreation state, {
  required bool busy,
  required Future<void> Function(Future<void> Function()) run,
}) {
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
  final l10n = appLocalizationsOf(context);

  return ChargedReviewDialog(
    title: l10n.createSnapshot,
    destination: l10n.uploadReviewTo(drive.name),
    primaryLabel: l10n.createSnapshot,
    busy: busy,
    leading: [
      const SizedBox(height: ArDriveSpacing.md),
      Text.rich(
        TextSpan(
          children: splitTranslationsWithMultipleStyles(
            originalText: l10n.createSnapshotExplanation(drive.name),
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
    // The snapshot is the one thing uploaded: its size is in its row.
    files: [
      (
        name: drive.name,
        size: state.snapshotSize,
        contentType: 'application/json',
      ),
    ],
    method: state.uploadMethod,
    totalSize: state.snapshotSize,
    costEstimateAr: state.costEstimateAr,
    costEstimateTurbo: state.costEstimateTurbo,
    turboBalance: state.turboBalance,
    turboCredits: state.turboCredits,
    arBalance: state.arBalance,
    sufficientArBalance: state.sufficientBalanceToPayWithAr,
    freeStatus: state.freeStatus,
    turboUnreachable: state.turboUnreachable,
    onMethodChanged: createSnapshotCubit.setUploadMethod,
    refresh: createSnapshotCubit.refreshTurboBalance,
    onConfirm: (_) => run(() async {
      logger.i('Confirming snapshot creation');
      await createSnapshotCubit.confirmSnapshotCreation();
    }),
    onCancel: () {
      logger.i('Canceling snapshot creation');
      Navigator.of(context).pop();
    },
  );
}

import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_bloc.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_event.dart';
import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/components/payment_method_selector_widget.dart';
import 'package:ardrive/components/turbo_free_status_message.dart';
import 'package:ardrive/drive_state/data/arweave_drive_state_uploader.dart';
import 'package:ardrive/drive_state/domain/drive_state_creation_service.dart';
import 'package:ardrive/drive_state/domain/drive_state_publish_cost.dart';
import 'package:ardrive/drive_state/domain/drive_state_sync_skip_status.dart';
import 'package:ardrive/drive_state/domain/drive_state_uploader.dart';
import 'package:ardrive/drive_state/presentation/drive_state_creation_cubit/drive_state_creation_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/turbo/topup/views/topup_modal.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pst/pst.dart';

/// The user-facing half of drive state creation.
///
/// The strings are in the `.arb` files, except the sentences the cubit and the
/// service compose themselves (a refusal's reason, a failure's message). The
/// shared components this modal reuses, [PaymentMethodSelector] and
/// [TurboFreeStatusMessage], carry their own localisation.
///
/// The modal's job is to make the confirm button an informed click. It shows
/// what would be published — the drive, how many entities, how large, and the
/// block range the artifact claims — because that claim is what an importer
/// trusts and it cannot be withdrawn once it is on chain. And it shows the
/// price, in the payment method that would be charged, because the other
/// thing that cannot be withdrawn is the money.

Future<void> promptToCreateDriveState(
  BuildContext context, {
  required Drive drive,
}) {
  final syncCubit = context.read<SyncCubit>();
  final driveDao = context.read<DriveDao>();
  final configService = context.read<ConfigService>();
  final paymentService = context.read<PaymentService>();
  final profileCubit = context.read<ProfileCubit>();
  final promptToSnapshotBloc = context.read<PromptToSnapshotBloc>();

  return showArDriveDialog(
    context,
    // Closed only by its own buttons, as the snapshot dialog before it was.
    // A click outside closed it mid-export, which left the export running
    // and hid the result of an upload already paid for.
    barrierDismissible: false,
    content: BlocProvider(
      create: (_) => DriveStateCreationCubit(
        driveId: drive.id,
        service: DriveStateCreationService(
          driveDao: driveDao,
          skipSource: SyncCubitDriveStateSkipSource(syncCubit),
        ),
        uploader: _uploaderFor(context, configService, profileCubit),
        costEstimator: DriveStatePublishCostEstimator(
          arweave: context.read<ArweaveService>(),
          paymentService: paymentService,
          pst: context.read<PstService>(),
          turboBalanceRetriever: TurboBalanceRetriever(
            paymentService: paymentService,
          ),
          configService: configService,
        ),
        profileCubit: profileCubit,
        driveDao: driveDao,
        // A published snapshot answers "Snapshot recommended", as the older
        // snapshot dialog's DriveSnapshotted does. The count is reset here,
        // synchronously, because the Snapshots tab re-reads it as soon as
        // the new snapshot is announced, before the bloc handles an event.
        onPublished: () {
          CountOfTxsSyncedWithGql.resetForDrive(drive.id);
          promptToSnapshotBloc.add(DriveSnapshotted(driveId: drive.id));
        },
      )..prepare(),
      child: DriveStateCreationModal(driveName: drive.name),
    ),
  );
}

/// The second half of the publishing rail.
///
/// `AppConfig.enableDriveStatePublishing` already decides whether the New menu
/// offers this flow at all. This decides whether the flow has anything behind
/// its confirm button, and it is the check that matters: a menu gate can be
/// bypassed by a future caller opening the modal directly, and this cannot.
/// With the flag off there is no object in the cubit that knows how to reach a
/// network.
DriveStateUploader _uploaderFor(
  BuildContext context,
  ConfigService configService,
  ProfileCubit profileCubit,
) =>
    driveStateUploaderFor(
      publishingEnabled: configService.config.enableDriveStatePublishing,
      whenEnabled: () => ArweaveDriveStateUploader(
        arweave: context.read<ArweaveService>(),
        turboUploadService: context.read<TurboUploadService>(),
        profileCubit: profileCubit,
        tabVisibility: TabVisibilitySingleton(),
      ),
    );

class DriveStateCreationModal extends StatelessWidget {
  final String driveName;

  const DriveStateCreationModal({super.key, required this.driveName});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DriveStateCreationCubit, DriveStateCreationState>(
      builder: (context, state) {
        if (state is DriveStateCreationPreparing ||
            state is DriveStateCreationInitial) {
          return _preparingModal(context, driveName);
        }

        if (state is DriveStateCreationRefused) {
          return _refusedModal(context, state);
        }

        if (state is DriveStateCreationReady) {
          return _confirmModal(context, state);
        }

        if (state is DriveStateCreationPublishing) {
          return _publishingModal(context);
        }

        if (state is DriveStateCreationPublished) {
          return _publishedModal(context, state);
        }

        return _failureModal(
          context,
          (state as DriveStateCreationFailure).message,
        );
      },
    );
  }
}

// Every state below passes `scrollableContent: true`, and none of them is free
// to stop.
//
// Not one of them controls the height of what it renders: the drive name, the
// refusal sentence, the uploader's failure message and the transaction id all
// arrive from somewhere else and can be any length. Left unbounded, a long one
// overflows a short screen and takes the Close button off the bottom with it —
// leaving the barrier as the only way out of the modal that was trying to
// explain why something had been refused. Bounded, the body scrolls and the
// button stays reachable.
//
// It is opt-in on `ArDriveStandardModalNew` because content that manages its
// own height — an `Expanded`, a `ListView` — breaks under a scroll view. None
// of these do.

Widget _preparingModal(BuildContext context, String driveName) {
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
  final l10n = appLocalizationsOf(context);

  return ArDriveStandardModalNew(
    title: l10n.snapshotPreparing,
    scrollableContent: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.snapshotPreparingBody(driveName),
          style: typography.paragraphNormal(color: colorTokens.textMid),
        ),
        const SizedBox(height: ArDriveSpacing.md),
        const Center(child: ArDriveSpinner(size: ArDriveSpinnerSize.large)),
      ],
    ),
    actions: [
      ModalAction.dismiss(
        title: l10n.cancelEmphasized,
        action: () => Navigator.of(context).pop(),
      ),
    ],
  );
}

/// The D3 rail, rendered.
///
/// It has no confirm button, and there is no override. A refusal here is the
/// difference between a drive that syncs slowly and a drive whose gap is
/// permanent, so the modal spends its words on what to do next rather than on
/// offering a way past.
Widget _refusedModal(BuildContext context, DriveStateCreationRefused state) {
  final l10n = appLocalizationsOf(context);

  return ArDriveStandardModalNew(
    title: l10n.createSnapshot,
    scrollableContent: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.isSyncGap) ...[
          ArDriveNotice(
            type: ArDriveNoticeType.warning,
            message: l10n.snapshotGapNotice,
          ),
          const SizedBox(height: ArDriveSpacing.md),
        ],
        ArDriveNotice(
          type: ArDriveNoticeType.error,
          message: state.reason,
        ),
      ],
    ),
    actions: [
      ModalAction.close(
        title: l10n.close,
        action: () => Navigator.of(context).pop(),
      ),
    ],
  );
}

/// What would be published, what it costs, and the only button that
/// publishes it.
Widget _confirmModal(
  BuildContext context,
  DriveStateCreationReady state,
) {
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
  final cubit = context.read<DriveStateCreationCubit>();
  final l10n = appLocalizationsOf(context);

  return ArDriveStandardModalNew(
    title: l10n.createSnapshot,
    scrollableContent: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          state.artifact.isEncrypted
              ? l10n.snapshotWhatItDoesEncrypted
              : l10n.snapshotWhatItDoes,
          style: typography.paragraphNormal(color: colorTokens.textMid),
        ),
        const SizedBox(height: ArDriveSpacing.md),
        _summary(context, state),
        const SizedBox(height: ArDriveSpacing.md),
        TurboFreeStatusMessage(
          status: state.cost.freeStatus,
          padding: const EdgeInsets.only(bottom: ArDriveSpacing.sm),
        ),
        // Free means Turbo bills nothing, so there is no method to choose
        // and no balance that could be short. The same rule the snapshot
        // dialog applies.
        if (!state.cost.isFree)
          PaymentMethodSelector(
            uploadMethodInfo: _paymentMethodInfo(state),
            onTurboTopupSucess: cubit.refreshTurboBalance,
            onArSelect: () => cubit.setUploadMethod(UploadMethod.ar),
            onTurboSelect: () => cubit.setUploadMethod(UploadMethod.turbo),
          ),
        if (state.cost.isUnaffordable) ...[
          const SizedBox(height: ArDriveSpacing.sm),
          ArDriveNotice(
            type: ArDriveNoticeType.error,
            message: l10n.snapshotUnaffordable,
            // The way on: Turbo Credits pay for a snapshot.
            actionLabel: l10n.buyCredits,
            onAction: () => showTurboTopupModal(
              context,
              onSuccess: cubit.refreshTurboBalance,
            ),
          ),
        ],
        const SizedBox(height: ArDriveSpacing.md),
        Text(
          l10n.snapshotNothingUploaded,
          style: typography.paragraphSmall(color: colorTokens.textLow),
        ),
      ],
    ),
    actions: [
      ModalAction.close(
        title: l10n.cancelEmphasized,
        action: () => Navigator.of(context).pop(),
      ),
      ModalAction(
        title: l10n.createSnapshot,
        // The one place in the app that spends money on an artifact, and it
        // is off unless the chosen method can actually pay for it. The cubit
        // refuses independently; this is the half the user can see.
        isEnable: state.canPublish,
        action: () => cubit.publish(),
      ),
    ],
  );
}

/// Feeds the shared [PaymentMethodSelector] rather than restating its layout.
///
/// `freeStatus` is deliberately [FreeUploadStatus.notEligible]: the free
/// message is rendered above by [TurboFreeStatusMessage], and the selector is
/// only built at all when the upload is not free.
UploadPaymentMethodInfo _paymentMethodInfo(DriveStateCreationReady state) =>
    UploadPaymentMethodInfo(
      uploadMethod: state.method,
      totalSize: state.artifact.sizeInBytes,
      costEstimateAr: state.cost.costEstimateAr,
      costEstimateTurbo: state.cost.costEstimateTurbo,
      hasNoTurboBalance: state.cost.hasNoTurboBalance,
      isTurboUploadPossible: state.cost.isTurboUploadPossible,
      arBalance: state.cost.arBalance,
      sufficientArBalance: state.cost.sufficientArBalance,
      turboCredits: state.cost.turboCredits,
      sufficentCreditsBalance: state.cost.sufficientTurboBalance,
      freeStatus: FreeUploadStatus.notEligible,
    );

Widget _summary(BuildContext context, DriveStateCreationReady state) {
  final artifact = state.artifact;
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
  final l10n = appLocalizationsOf(context);

  return Container(
    padding: const EdgeInsets.all(ArDriveSpacing.sm),
    decoration: BoxDecoration(
      color: colorTokens.containerL1,
      borderRadius: BorderRadius.circular(ArDriveRadius.md),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _summaryRow(context, l10n.snapshotSummaryDrive, artifact.driveName),
        _summaryRow(
            context, l10n.snapshotSummaryItems, '${artifact.entityCount}'),
        _summaryRow(
          context,
          l10n.snapshotSummarySize,
          filesize(artifact.sizeInBytes),
        ),
        _summaryRow(
          context,
          l10n.snapshotSummaryBlocks,
          l10n.snapshotBlocksRange(artifact.blockStart, artifact.blockEnd),
        ),
      ],
    ),
  );
}

Widget _summaryRow(BuildContext context, String label, String value) {
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: ArDriveSpacing.xxs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: typography.paragraphSmall(color: colorTokens.textLow),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: typography.paragraphSmall(
              fontWeight: ArFontWeight.semiBold,
              color: colorTokens.textHigh,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The upload runs: the primary is busy and Cancel is held, as the dialog
/// that started it was. Closing now would hide the result of a payment.
Widget _publishingModal(BuildContext context) {
  final l10n = appLocalizationsOf(context);

  return ArDriveStandardModalNew(
    title: l10n.createSnapshot,
    scrollableContent: true,
    content: ArDriveNotice(
      type: ArDriveNoticeType.info,
      message: l10n.snapshotCreating,
      leading: const ArDriveSpinner(),
    ),
    actions: [
      ModalAction.close(
        title: l10n.cancelEmphasized,
        isEnable: false,
        action: () {},
      ),
      ModalAction(
        title: l10n.createSnapshot,
        isLoading: true,
        action: () {},
      ),
    ],
  );
}

Widget _publishedModal(
  BuildContext context,
  DriveStateCreationPublished state,
) {
  final l10n = appLocalizationsOf(context);

  // No transaction id: the Snapshots tab lists the new snapshot straight
  // away, with its id to copy and its confirmation status, which is where a
  // user who wants either looks.
  return ArDriveStandardModalNew(
    title: l10n.snapshotSuceeded,
    scrollableContent: true,
    description: l10n.snapshotPublishedBody(state.artifact.driveName),
    actions: [
      ModalAction.close(
        title: l10n.close,
        action: () => Navigator.of(context).pop(),
      ),
    ],
  );
}

/// The failure stays in the dialog, in a notice, with Try again: it prepares
/// the snapshot anew, and nothing is uploaded before the confirm button.
Widget _failureModal(BuildContext context, String message) {
  final l10n = appLocalizationsOf(context);

  return ArDriveStandardModalNew(
    title: l10n.snapshotFailed,
    scrollableContent: true,
    content: ArDriveNotice(
      type: ArDriveNoticeType.error,
      message: message,
    ),
    actions: [
      ModalAction.close(
        title: l10n.close,
        action: () => Navigator.of(context).pop(),
      ),
      ModalAction(
        title: l10n.tryAgainEmphasized,
        action: () => context.read<DriveStateCreationCubit>().prepare(),
      ),
    ],
  );
}

import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_bloc.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_event.dart';
import 'package:ardrive/components/payment_method_selector_widget.dart';
import 'package:ardrive/components/charged_review_dialog.dart';
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
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
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
        // As the publish dialog does: a running sync may cover the drive
        // already, so wait for it, and sync only if the drive still can't be
        // confirmed complete. Skipped items need the deep sync asked for.
        syncDrive: (
            {required deep, required force, required isCancelled}) async {
          await syncCubit.waitCurrentSync();
          if (syncCubit.state is SyncLoadingDrives) {
            await syncCubit.waitForDriveListRefresh();
          }
          if (isCancelled()) return false;
          if (!deep &&
              !force &&
              SyncCubitDriveStateSkipSource(syncCubit)
                  .statusFor(drive.id)
                  .isClean) {
            return true;
          }
          // False also for a sync that ran and failed, which the check that
          // follows describes. Only a refused start is "couldn't start".
          final ran = await syncCubit.startSyncForDrive(
            driveId: drive.id,
            deepSync: deep,
          );
          return ran || syncCubit.lastSingleSyncRefusal == null;
        },
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

        if (state is DriveStateCreationSyncing) {
          return _syncingModal(context);
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

        return _failureModal(context, state as DriveStateCreationFailure);
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
/// permanent, so the modal offers what to do next, a sync where one can
/// clear it, rather than a way past.
Widget _refusedModal(BuildContext context, DriveStateCreationRefused state) {
  final l10n = appLocalizationsOf(context);

  return ArDriveStandardModalNew(
    title: l10n.createSnapshot,
    scrollableContent: true,
    content: ArDriveNotice(
      type: state.canSync ? ArDriveNoticeType.warning : ArDriveNoticeType.error,
      message: state.syncDidNotStart
          ? l10n.snapshotSyncCouldNotStart
          : _refusalText(l10n, state.refusal),
    ),
    actions: [
      ModalAction.close(
        title: l10n.close,
        action: () => Navigator.of(context).pop(),
      ),
      if (state.canSync)
        ModalAction(
          title: l10n.publishSyncDrive,
          action: () =>
              context.read<DriveStateCreationCubit>().syncThenPrepare(),
        ),
    ],
  );
}

/// Syncing before preparing again. Cancel closes the dialog; the sync goes
/// on, as any sync does.
Widget _syncingModal(BuildContext context) {
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
  final l10n = appLocalizationsOf(context);

  return ArDriveStandardModalNew(
    title: l10n.createSnapshot,
    scrollableContent: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.publishSyncingDrive,
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

  return ChargedReviewDialog(
    title: l10n.createSnapshot,
    destination: l10n.uploadReviewTo(state.artifact.driveName),
    primaryLabel: l10n.createSnapshot,
    // The upload starts a state of its own, which holds Cancel.
    busy: false,
    leading: [
      const SizedBox(height: ArDriveSpacing.md),
      Text(
        state.artifact.isEncrypted
            ? l10n.snapshotWhatItDoesEncrypted
            : l10n.snapshotWhatItDoes,
        style: typography.paragraphNormal(color: colorTokens.textMid),
      ),
      const SizedBox(height: ArDriveSpacing.md),
      _summary(context, state),
    ],
    files: [
      (
        name: state.artifact.driveName,
        size: state.artifact.sizeInBytes,
        contentType: 'application/json',
      ),
    ],
    method: state.method,
    totalSize: state.artifact.sizeInBytes,
    costEstimateAr: state.cost.costEstimateAr,
    costEstimateTurbo:
        state.cost.isTurboUploadPossible ? state.cost.costEstimateTurbo : null,
    turboBalance: state.cost.turboBalance,
    turboCredits: state.cost.turboCredits,
    arBalance: state.cost.arBalance,
    sufficientArBalance: state.cost.sufficientArBalance,
    freeStatus: state.cost.freeStatus,
    turboUnreachable: state.cost.turboUnreachable,
    onMethodChanged: cubit.setUploadMethod,
    refresh: cubit.refreshTurboBalance,
    // The cubit refuses on its own what the method can't pay for.
    onConfirm: (_) => cubit.publish(),
    onCancel: () => Navigator.of(context).pop(),
  );
}

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
        _summaryRow(
            context, l10n.snapshotSummaryItems, '${artifact.entityCount}'),
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

/// The failure stays in the dialog, in a notice. Try again prepares the
/// snapshot anew, and is offered only where nothing was posted: after an
/// upload that may have been paid for, a second attempt would pay twice.
Widget _failureModal(BuildContext context, DriveStateCreationFailure state) {
  final l10n = appLocalizationsOf(context);

  return ArDriveStandardModalNew(
    title: l10n.snapshotFailed,
    scrollableContent: true,
    content: ArDriveNotice(
      type: ArDriveNoticeType.error,
      message: _failureText(l10n, state),
    ),
    actions: [
      ModalAction.close(
        title: l10n.close,
        action: () => Navigator.of(context).pop(),
      ),
      if (state.canTryAgain)
        ModalAction(
          title: l10n.tryAgainEmphasized,
          action: () => context.read<DriveStateCreationCubit>().prepare(),
        ),
    ],
  );
}

/// What a refusal says, in the user's language. The service's own sentence is
/// English, for the log.
String _refusalText(AppLocalizations l10n, DriveStateCreationRefusal refusal) =>
    switch (refusal) {
      DriveStateCreationRefusal.syncSkippedEntities =>
        l10n.snapshotRefusedSyncSkipped,
      DriveStateCreationRefusal.skipStateUnknown =>
        l10n.snapshotRefusedSyncUnknown,
      DriveStateCreationRefusal.driveNotFound => l10n.snapshotRefusedNotFound,
      DriveStateCreationRefusal.protectionUnavailable =>
        l10n.snapshotRefusedProtection,
      DriveStateCreationRefusal.notDriveOwner => l10n.snapshotRefusedNotOwner,
      DriveStateCreationRefusal.noWatermark => l10n.snapshotRefusedNoWatermark,
      DriveStateCreationRefusal.payloadTooLarge => l10n.snapshotRefusedTooLarge,
      DriveStateCreationRefusal.unconfirmedChanges =>
        l10n.snapshotRefusedUnconfirmed,
      DriveStateCreationRefusal.sealFailed ||
      DriveStateCreationRefusal.cancelled =>
        l10n.snapshotRefusedSealFailed,
    };

String _failureText(AppLocalizations l10n, DriveStateCreationFailure state) =>
    switch (state.kind) {
      DriveStateCreationFailureKind.costTimeout =>
        l10n.snapshotFailureCostTimeout,
      DriveStateCreationFailureKind.costUnknown =>
        l10n.snapshotFailureCostUnknown,
      DriveStateCreationFailureKind.prepareFailed =>
        l10n.snapshotFailurePrepare,
      DriveStateCreationFailureKind.notEnabled =>
        l10n.snapshotFailureNotEnabled,
      DriveStateCreationFailureKind.notLoggedIn =>
        l10n.snapshotFailureNotLoggedIn,
      DriveStateCreationFailureKind.walletChanged =>
        l10n.snapshotFailureWalletChanged,
      DriveStateCreationFailureKind.walletUnavailable =>
        l10n.snapshotFailureWalletUnavailable,
      DriveStateCreationFailureKind.paymentDeclined =>
        l10n.snapshotFailurePaymentDeclined,
      DriveStateCreationFailureKind.publishFailed =>
        l10n.snapshotFailurePublish,
      DriveStateCreationFailureKind.publishUncertain =>
        l10n.snapshotFailureUncertain(state.txId ?? ''),
      DriveStateCreationFailureKind.publishThrew => l10n.snapshotFailureThrew,
    };

import 'package:ardrive/blocs/profile/profile_cubit.dart';
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
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/utils.dart' show winstonToAr;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pst/pst.dart';

/// The user-facing half of drive state creation.
///
/// Every string written here is hardcoded English, matching the
/// `statusMessage` strings this surface already carries in
/// `sync_repository.dart`. Adding `.arb` keys would put five locales' worth of
/// translation in front of a feature that is not yet published to chain; when
/// it ships, these move across in one pass. The shared components this modal
/// reuses — [PaymentMethodSelector], [TurboFreeStatusMessage] — carry their
/// own localisation, and are left as they are rather than forked to match.
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

  return showArDriveDialog(
    context,
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

const _title = 'Publish drive state';

Widget _preparingModal(BuildContext context, String driveName) {
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

  return ArDriveStandardModalNew(
    title: _title,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Preparing an artifact for $driveName. Nothing has been uploaded '
          'yet.',
          style: typography.paragraphNormal(color: colorTokens.textMid),
        ),
        const SizedBox(height: 16),
        const Center(child: CircularProgressIndicator()),
      ],
    ),
    actions: [
      ModalAction(
        title: 'Cancel',
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
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

  return ArDriveStandardModalNew(
    title: _title,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.isSyncGap)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: colorTokens.containerL1,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ArDriveIcons.triangle(
                  size: 16,
                  color: colorTokens.strokeRed,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'A drive state artifact is permanent. Publishing one from '
                    'an incomplete drive would record the gap forever.',
                    style:
                        typography.paragraphSmall(color: colorTokens.textMid),
                  ),
                ),
              ],
            ),
          ),
        Text(
          state.reason,
          style: typography.paragraphNormal(color: colorTokens.textHigh),
        ),
      ],
    ),
    actions: [
      ModalAction(
        title: 'Close',
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

  return ArDriveStandardModalNew(
    title: _title,
    scrollableContent: true,
    content: ConstrainedBox(
      // Inside the content, so the modal's own responsive cap still applies.
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This publishes a snapshot of this drive\'s current state to '
            'Arweave, encrypted with your drive key. It is permanent and '
            'cannot be removed.',
            style: typography.paragraphNormal(color: colorTokens.textMid),
          ),
          const SizedBox(height: 16),
          _summary(context, state),
          const SizedBox(height: 16),
          TurboFreeStatusMessage(
            status: state.cost.freeStatus,
            padding: const EdgeInsets.only(bottom: 12),
          ),
          // Free means Turbo bills nothing, so there is no method to choose
          // and no balance that could be short. The same rule the snapshot
          // dialog applies.
          if (!state.cost.isFree)
            PaymentMethodSelector(
              useNewArDriveUI: true,
              uploadMethodInfo: _paymentMethodInfo(state),
              onTurboTopupSucess: cubit.refreshTurboBalance,
              onArSelect: () => cubit.setUploadMethod(UploadMethod.ar),
              onTurboSelect: () => cubit.setUploadMethod(UploadMethod.turbo),
            ),
          if (state.cost.isUnaffordable) ...[
            const SizedBox(height: 12),
            Text(
              'Neither your AR balance nor your Turbo Credits cover this '
              'artifact, so it cannot be published yet.',
              style: typography.paragraphSmall(color: colorTokens.textRed),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Nothing has been uploaded yet.',
            style: typography.paragraphSmall(color: colorTokens.textLow),
          ),
        ],
      ),
    ),
    actions: [
      ModalAction(
        title: 'Cancel',
        action: () => Navigator.of(context).pop(),
      ),
      ModalAction(
        title: 'Publish',
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

  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: colorTokens.containerL1,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _summaryRow(context, 'Drive', artifact.driveName),
        _summaryRow(context, 'Entities', '${artifact.entityCount}'),
        _summaryRow(context, 'Size', filesize(artifact.sizeInBytes)),
        _summaryRow(
          context,
          'Blocks',
          '${artifact.blockStart} to ${artifact.blockEnd}',
        ),
        _summaryRow(context, 'Cost', _costLabel(state)),
      ],
    ),
  );
}

/// The headline price, in the terms of the method that would actually be
/// charged.
///
/// The selector below repeats both costs and lets the user switch; this line
/// exists so the summary of "what this does" ends with what it takes, rather
/// than leaving the price to a widget further down that a short viewport may
/// have scrolled away. It follows the selection, so the two can never read
/// differently.
String _costLabel(DriveStateCreationReady state) {
  final cost = state.cost;
  if (cost.isFree) return 'Free, thanks to Turbo';

  return switch (state.effectiveMethod) {
    UploadMethod.turbo =>
      '${winstonToAr(cost.costEstimateTurbo.totalCost)} Credits',
    UploadMethod.ar => '${winstonToAr(cost.costEstimateAr.totalCost)} AR',
  };
}

Widget _summaryRow(BuildContext context, String label, String value) {
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
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

Widget _publishingModal(BuildContext context) {
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

  return ArDriveStandardModalNew(
    title: _title,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Publishing...',
          style: typography.paragraphNormal(color: colorTokens.textMid),
        ),
        const SizedBox(height: 16),
        const Center(child: CircularProgressIndicator()),
      ],
    ),
  );
}

Widget _publishedModal(
  BuildContext context,
  DriveStateCreationPublished state,
) {
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

  return ArDriveStandardModalNew(
    title: _title,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${state.artifact.driveName} published its state as '
          '${state.txId}.',
          style: typography.paragraphNormal(color: colorTokens.textMid),
        ),
      ],
    ),
    actions: [
      ModalAction(
        title: 'Close',
        action: () => Navigator.of(context).pop(),
      ),
    ],
  );
}

Widget _failureModal(BuildContext context, String message) {
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

  return ArDriveStandardModalNew(
    title: _title,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: typography.paragraphNormal(color: colorTokens.textHigh),
        ),
      ],
    ),
    actions: [
      ModalAction(
        title: 'Close',
        action: () => Navigator.of(context).pop(),
      ),
    ],
  );
}

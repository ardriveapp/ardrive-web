import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/drive_state/domain/drive_state_creation_service.dart';
import 'package:ardrive/drive_state/domain/drive_state_sync_skip_status.dart';
import 'package:ardrive/drive_state/domain/drive_state_uploader.dart';
import 'package:ardrive/drive_state/presentation/drive_state_creation_cubit/drive_state_creation_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The user-facing half of drive state creation.
///
/// Every string here is hardcoded English, matching the `statusMessage`
/// strings this surface already carries in `sync_repository.dart`. Adding
/// `.arb` keys would put five locales' worth of translation in front of a
/// feature that is not yet published to chain; when it ships, these move
/// across in one pass.
///
/// The modal's job is to make the confirm button an informed click. It shows
/// what would be published — the drive, how many entities, how large, and the
/// block range the artifact claims — because that claim is what an importer
/// trusts and it cannot be withdrawn once it is on chain.

Future<void> promptToCreateDriveState(
  BuildContext context, {
  required Drive drive,
}) {
  final syncCubit = context.read<SyncCubit>();
  final driveDao = context.read<DriveDao>();

  return showArDriveDialog(
    context,
    content: BlocProvider(
      create: (_) => DriveStateCreationCubit(
        driveId: drive.id,
        service: DriveStateCreationService(
          driveDao: driveDao,
          skipSource: SyncCubitDriveStateSkipSource(syncCubit),
        ),
        // D8: the seam is wired, and what is behind it publishes nothing.
        uploader: const UnwiredDriveStateUploader(),
        profileCubit: context.read<ProfileCubit>(),
        driveDao: driveDao,
      )..prepare(),
      child: DriveStateCreationModal(driveName: drive.name),
    ),
  );
}

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
          return _confirmModal(context, state.artifact);
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

/// What would be published, and the only button that publishes it.
Widget _confirmModal(
  BuildContext context,
  PreparedDriveStateArtifact artifact,
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
          _summary(context, artifact),
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
        action: () => cubit.publish(),
      ),
    ],
  );
}

Widget _summary(BuildContext context, PreparedDriveStateArtifact artifact) {
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
      ],
    ),
  );
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

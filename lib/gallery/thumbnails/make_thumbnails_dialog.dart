import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/payment_required_notice.dart';
import 'package:ardrive/components/turbo_credits_funding.dart';
import 'package:ardrive/components/upload_review_dialog.dart';
import 'package:ardrive/core/upload/metadata_write_cost.dart';
import 'package:ardrive/drive_explorer/thumbnail/repository/thumbnail_repository.dart';
import 'package:ardrive/gallery/thumbnails/make_thumbnails_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Make thumbnails for the images in [folderId] that lack them: the review
/// with its price, then the work, which stays in the dialog until it ends or
/// is stopped.
Future<void> showMakeThumbnailsDialog(
  BuildContext context, {
  required Drive drive,
  required String folderId,
  required String folderName,
}) {
  final driveDao = context.read<DriveDao>();
  // Not every menu that offers it sits in the explorer.
  DriveDetailCubit? detail;
  try {
    detail = context.read<DriveDetailCubit>();
  } catch (_) {}
  return showArDriveDialog(
    context,
    // Only its own buttons close it, and they wait while it works.
    barrierDismissible: false,
    content: BlocProvider(
      create: (context) => MakeThumbnailsCubit(
        isPrivate: drive.isPrivate,
        findImages: () => imagesLackingThumbnailsInFolder(
          driveDao,
          driveId: drive.id,
          folderId: folderId,
        ),
        thumbnails: context.read<ThumbnailRepository>(),
        costReader: MetadataWriteCostReader(
          payments: context.read<PaymentService>(),
          turbo: context.read<TurboUploadService>(),
          arweave: context.read<ArweaveService>(),
        ),
        profileCubit: context.read<ProfileCubit>(),
      )..load(),
      child: MakeThumbnailsDialog(
        folderName: folderName,
        isPrivate: drive.isPrivate,
        onMade: detail?.refreshDriveDataTable,
      ),
    ),
  );
}

class MakeThumbnailsDialog extends StatelessWidget {
  const MakeThumbnailsDialog({
    super.key,
    required this.folderName,
    required this.isPrivate,
    this.onMade,
  });

  final String folderName;
  final bool isPrivate;

  /// After each image's thumbnails land, so the explorer shows them.
  final VoidCallback? onMade;

  @override
  Widget build(BuildContext context) {
    final l10n = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    void close() => Navigator.of(context).pop();

    Widget say(String text) => Text(
          text,
          style: typography.paragraphNormal(color: colorTokens.textMid),
        );

    return BlocConsumer<MakeThumbnailsCubit, MakeThumbnailsState>(
      listenWhen: (a, b) => b.made > a.made,
      // Each one appears in the gallery as it lands.
      listener: (context, _) => onMade?.call(),
      builder: (context, state) {
        final cubit = context.read<MakeThumbnailsCubit>();
        switch (state.phase) {
          case MakeThumbnailsPhase.loading:
            return ArDriveStandardModalNew(
              title: l10n.makeThumbnails,
              content: const SizedBox(
                height: 48,
                child: Center(
                    child: ArDriveSpinner(size: ArDriveSpinnerSize.large)),
              ),
              actions: [
                ModalAction.close(action: close, title: l10n.cancel),
              ],
            );
          case MakeThumbnailsPhase.nothingToDo:
            return ArDriveStandardModalNew(
              title: l10n.makeThumbnails,
              content: say(l10n.makeThumbnailsNothingToDo),
              actions: [ModalAction.close(action: close, title: l10n.close)],
            );
          case MakeThumbnailsPhase.ready:
            return UploadReviewDialog(
              title: l10n.makeThumbnails,
              destination: l10n.makeThumbnailsIn(state.total, folderName),
              destinationIsPrivate: isPrivate,
              files: const [],
              leading: [
                if (!isPrivate) ...[
                  say(l10n.makeThumbnailsPublicNote),
                  const SizedBox(height: ArDriveSpacing.md),
                ],
              ],
              summary: state.summary,
              primaryLabel: l10n.makeThumbnails,
              subject: ReviewCostSubject.change,
              priceUnavailableMessage:
                  state.pricingFailed ? l10n.priceUnavailableTryAgain : null,
              onUpload: (_) => cubit.start(),
              onCancel: close,
              funding: TurboCreditsFunding(
                context,
                onRefresh: cubit.readPrice,
              ),
            );
          case MakeThumbnailsPhase.working:
          case MakeThumbnailsPhase.stopping:
            final total = state.total == 0 ? 1 : state.total;
            return ArDriveStandardModalNew(
              title: l10n.makeThumbnails,
              hasCloseButton: false,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.makeThumbnailsProgress(state.made, state.total),
                    style: typography.paragraphLarge(
                      color: colorTokens.textHigh,
                      fontWeight: ArFontWeight.semiBold,
                    ),
                  ),
                  const SizedBox(height: ArDriveSpacing.sm),
                  ArDriveLinearProgress(
                    value: (state.made + state.failed + state.nothingToAdd) /
                        total,
                  ),
                  const SizedBox(height: ArDriveSpacing.sm),
                  say(l10n.makeThumbnailsProgressNote),
                ],
              ),
              actions: [
                ModalAction(
                  action: cubit.stop,
                  title: l10n.makeThumbnailsStop,
                  isEnable: state.phase == MakeThumbnailsPhase.working,
                ),
                ModalAction(
                  action: () {},
                  title: l10n.makeThumbnails,
                  isEnable: true,
                  isLoading: true,
                ),
              ],
            );
          case MakeThumbnailsPhase.done:
            return ArDriveStandardModalNew(
              title: l10n.makeThumbnails,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  say(state.loadFailed
                      ? l10n.actionFailedTryAgain
                      : l10n.makeThumbnailsMade(state.made)),
                  if (state.failed > 0) ...[
                    const SizedBox(height: ArDriveSpacing.sm),
                    say(l10n.makeThumbnailsFailed(state.failed)),
                  ],
                  if (state.paymentRequired) ...[
                    const SizedBox(height: ArDriveSpacing.md),
                    const PaymentRequiredNotice(),
                  ],
                ],
              ),
              actions: [ModalAction.close(action: close, title: l10n.close)],
            );
        }
      },
    );
  }
}

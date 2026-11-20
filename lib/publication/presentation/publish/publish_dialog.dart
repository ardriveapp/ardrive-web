import 'package:ardrive/core/crypto/file_keys.dart';
import 'package:ardrive/arns/data/arns_change_executor.dart';
import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog_cubit.dart';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:ardrive/arns/domain/arns_nameable_item.dart';
import 'package:ardrive/arns/presentation/item/arns_item_names.dart';
import 'package:ardrive/arns/presentation/names/arns_names_cubit.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/publication/presentation/publish_to_web.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/components/charged_review_dialog.dart';
import 'package:ardrive/components/copyable_share_artifact.dart';
import 'package:ardrive/drive_state/data/arweave_drive_state_uploader.dart';
import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/domain/drive_state_creation_service.dart';
import 'package:ardrive/drive_state/domain/drive_state_publish_cost.dart';
import 'package:ardrive/drive_state/domain/drive_state_sync_skip_status.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/publication/data/publication_repository.dart';
import 'package:ardrive/publication/data/publication_uploader.dart';
import 'package:ardrive/publication/domain/file_page.dart';
import 'package:ardrive/publication/domain/publication_publisher.dart';
import 'package:ardrive/publication/domain/publication_scope.dart'
    show PublicationSummary;
import 'package:ardrive/publication/presentation/publications_cubit.dart';
import 'package:ardrive/publication/presentation/publish/publish_cubit.dart';
import 'package:ardrive/publication/presentation/publish/publish_look_step.dart';
import 'package:ardrive/publication/presentation/publish/published_view.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/arweave/graphql/graphql.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart'
    show EntityTag, TabVisibilitySingleton;
import 'package:ardrive/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:pst/pst.dart';

/// "Publish to web" on a drive ([folder] and [file] null), a folder or a
/// file: the published view when it is published already, else the publish
/// dialog (docs/PUBLICATIONS.md, "Entry points").
Future<void> promptToPublish(
  BuildContext context, {
  required Drive drive,
  FolderEntry? folder,
  FileEntry? file,
}) async {
  final publications = context.read<PublicationsCubit>();
  final known = await publications.publicationsOf(drive);
  if (!context.mounted) return;
  if (known == null) {
    final strings = appLocalizationsOf(context);
    return showArDriveDialog(
      context,
      content: ArDriveStandardModalNew(
        title: strings.publishToWeb,
        description: strings.publishCheckFailed,
        actions: [
          ModalAction.close(
            title: strings.close,
            action: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
  final publication =
      file != null ? known.ofFile(file.id) : known.of(folder?.id);
  if (publication != null) {
    return showPublishedView(
      context,
      drive: drive,
      folder: folder,
      file: file,
      publication: publication,
    );
  }
  return showPublishDialog(context, drive: drive, folder: folder, file: file);
}

/// The publish dialog. [previous] makes it an update of that publication,
/// opening on the look.
Future<void> showPublishDialog(
  BuildContext context, {
  required Drive drive,
  FolderEntry? folder,
  FileEntry? file,
  Publication? previous,
}) {
  final strings = appLocalizationsOf(context);
  final configService = context.read<ConfigService>();
  final paymentService = context.read<PaymentService>();
  final arweave = context.read<ArweaveService>();
  final driveDao = context.read<DriveDao>();
  final profileCubit = context.read<ProfileCubit>();
  final repository = context.read<PublicationRepository>();
  final turboUploadService = context.read<TurboUploadService>();
  final syncCubit = context.read<SyncCubit>();
  // Every publication is on one gateway, whatever the data gateway setting.
  String gatewayUrl() => configService.config.publicationGatewayUrl;
  final publisher = PublicationPublisher(
    uploader: PublicationUploader(
      arweave: arweave,
      turboUploadService: turboUploadService,
    ),
    // A publication may need a snapshot, and makes one only where snapshots
    // can be published at all.
    driveStateUploader: driveStateUploaderFor(
      publishingEnabled: configService.config.enableDriveStatePublishing,
      whenEnabled: () => ArweaveDriveStateUploader(
        arweave: arweave,
        turboUploadService: turboUploadService,
        profileCubit: profileCubit,
        tabVisibility: TabVisibilitySingleton(),
      ),
    ),
    repository: repository,
    gatewayUrl: gatewayUrl,
  );
  final dependencies = PublishDependencies(
    driveDao: driveDao,
    fileKeys: context.read<FileKeys>(),
    profileCubit: profileCubit,
    syncSkipSource: SyncCubitDriveStateSkipSource(context.read<SyncCubit>()),
    repository: repository,
    publisher: publisher,
    creationService: DriveStateCreationService(
      driveDao: driveDao,
      skipSource: SyncCubitDriveStateSkipSource(context.read<SyncCubit>()),
    ),
    discovery: GraphQLDriveStateDiscovery(graphQLRetry: arweave.graphQLRetry),
    costEstimator: DriveStatePublishCostEstimator(
      arweave: arweave,
      paymentService: paymentService,
      pst: context.read<PstService>(),
      turboBalanceRetriever:
          TurboBalanceRetriever(paymentService: paymentService),
      configService: configService,
      // Turbo's own limit, as the upload flow reads it.
      maxFreeItemBytes: () => turboUploadService.maxFreeItemSizeBytes,
    ),
    viewer: configService.config.publicationViewer,
    labels: PublicationLabels(
      filesPage: strings.publicationFilesPageLink,
      openPage: strings.publicationFilesOpen,
      moreFiles: strings.publicationFilesMore('{count}'),
      privatePage: strings.publicationPrivatePage,
    ),
    cardMark: () => loadAssetImage(Resources.images.brand.logo1),
    fileCountLabel: strings.publishFileCount,
    syncDrive: (driveId, {required deep, required isCancelled}) async {
      // A running sync may cover the drive already: wait for it, and sync
      // only if the drive still can't be confirmed complete. Not when items
      // were skipped: a plain sync clears that record without reading them,
      // so only the deep sync asked for will do.
      await syncCubit.waitCurrentSync();
      if (syncCubit.state is SyncLoadingDrives) {
        await syncCubit.waitForDriveListRefresh();
      }
      if (isCancelled()) return false;
      if (!deep &&
          SyncCubitDriveStateSkipSource(syncCubit).statusFor(driveId).isClean) {
        return true;
      }
      // False also for a sync that ran and failed, which the check that
      // follows describes. Only a refused start is "couldn't start".
      final ran =
          await syncCubit.startSyncForDrive(driveId: driveId, deepSync: deep);
      return ran || syncCubit.lastSingleSyncRefusal == null;
    },
    cipherOf: (dataTxId) async {
      try {
        final tx = await arweave
            .getTransactionDetails(dataTxId)
            .timeout(const Duration(seconds: 30));
        final cipher = tx?.getTag(EntityTag.cipher);
        final iv = tx?.getTag(EntityTag.cipherIv);
        return cipher == null || iv == null
            ? null
            : (cipher: cipher, cipherIv: iv);
      } catch (e) {
        logger.w('[publication] the file cipher could not be read: $e');
        return null;
      }
    },
  );
  // The app's messenger outlives the dialog, which may be closed while the
  // publish runs.
  final messenger = ScaffoldMessenger.maybeOf(context);
  return showArDriveDialog(
    context,
    // Closed only by its own buttons: a click outside must not hide a
    // publish already paid for.
    barrierDismissible: false,
    content: BlocProvider(
      create: (_) => PublishCubit(
        drive: drive,
        folder: folder,
        file: file,
        previous: previous,
        dependencies: dependencies,
        // The name step; a republish carries the names on the version it
        // replaces (docs/NAMES.md, Q12, Q29).
        names: createArNSFlowNameCubit(
          context,
          following: arnsNamesOnVersion(context, previous?.latest.txId),
          writesHint: false,
        ),
        onSettledAfterClose: (link) {
          if (messenger != null && messenger.mounted) {
            showPublishSettledNotice(messenger, strings, link);
          }
        },
      )..load(),
      child: const PublishDialog(),
    ),
  );
}

/// Tells the owner how a publish ended after its dialog was closed, in the
/// app's own snackbar: the page and a link to open it, or how to try again.
void showPublishSettledNotice(
  ScaffoldMessengerState messenger,
  AppLocalizations strings,
  String? link,
) {
  showArDriveToast(
    messenger,
    text:
        link != null ? strings.publishDoneTitle : strings.publishStoppedNotice,
    type: link != null ? ArDriveStatusType.success : ArDriveStatusType.warning,
    duration: const Duration(seconds: 10),
    actionLabel: link == null ? null : strings.publishOpen,
    onAction: link == null ? null : () => openUrl(url: link),
  );
}

/// An asset as a decoded image, for the generated card.
Future<ui.Image> loadAssetImage(String asset) async {
  final data = await rootBundle.load(asset);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  return (await codec.getNextFrame()).image;
}

class PublishDialog extends StatelessWidget {
  const PublishDialog({super.key});

  @override
  Widget build(BuildContext context) {
    // Back does not close a publish in progress; only its Close button
    // does, on purpose, and the app then says how it ended.
    return BlocSelector<PublishCubit, PublishState, bool>(
      selector: (state) => state.stage == PublishStage.publishing,
      builder: (context, publishing) => PopScope(
        canPop: !publishing,
        child: _content(),
      ),
    );
  }

  Widget _content() {
    return BlocBuilder<PublishCubit, PublishState>(
      builder: (context, state) {
        final strings = appLocalizationsOf(context);
        final cubit = context.read<PublishCubit>();
        final title =
            state.isUpdate ? strings.publishUpdateTitle : strings.publishToWeb;
        void close() => Navigator.of(context).pop();
        // A file starts with how it is published; a drive or folder starts
        // on the look.
        final total = cubit.isFile ? 3 : 2;

        switch (state.stage) {
          case PublishStage.loading:
            return _waiting(context, title, strings.publishGettingReady, close);
          case PublishStage.pricing:
            return _waiting(
                context, title, strings.publishWorkingOutCost, close);
          case PublishStage.syncing:
            return _waiting(context, title, strings.publishSyncingDrive, close);
          case PublishStage.blocked:
            return _modal(
              context,
              title: title,
              content: _Blocked(state: state),
              actions: [
                if (cubit.canSyncDrive) ...[
                  ModalAction.close(title: strings.close, action: close),
                  ModalAction(
                      title: strings.publishSyncDrive, action: cubit.syncDrive),
                ] else
                  ModalAction.close(title: strings.close, action: close),
              ],
            );
          case PublishStage.how:
            return _modal(
              context,
              title: title,
              step: strings.publishStepOf(1, 3),
              content: _How(state: state),
              actions: [
                ModalAction.close(title: strings.cancel, action: close),
                ModalAction(
                  title: strings.next,
                  isEnable: state.howIsReady,
                  action: cubit.next,
                ),
              ],
            );
          case PublishStage.itself:
            return _modal(
              context,
              title: title,
              content: _Itself(link: cubit.fileLink, file: cubit.file!),
              actions: [
                ModalAction.dismiss(title: strings.back, action: cubit.back),
                ModalAction(title: strings.doneEmphasized, action: close),
              ],
            );
          case PublishStage.look:
            // A picture from the drive is chosen in place of the look, and
            // Back returns to it. The look stays mounted under it, hidden,
            // so a keyword being typed and the opened options are still
            // there on return; the dialog's scroll is put back too.
            final choosing = state.choosingSlot;
            return _modal(
              context,
              title: choosing != null ? strings.publishChooseImageTitle : title,
              step: strings.publishStepOf(cubit.isFile ? 2 : 1, total),
              wide: true,
              content: KeepsScrollWhileAway(
                away: choosing != null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Offstage(
                      offstage: choosing != null,
                      child: ExcludeFocus(
                        excluding: choosing != null,
                        child: const PublishLookStep(),
                      ),
                    ),
                    if (choosing != null) ImageFromDriveChooser(slot: choosing),
                  ],
                ),
              ),
              actions: choosing != null
                  ? [
                      ModalAction.dismiss(
                          title: strings.back, action: cubit.closeImageChooser),
                    ]
                  : [
                      // The first step of a drive or folder has nothing to go
                      // back to.
                      if (cubit.isFile)
                        ModalAction.dismiss(
                            title: strings.back, action: cubit.back)
                      else
                        ModalAction.close(title: strings.cancel, action: close),
                      ModalAction(
                        title: strings.next,
                        isEnable: state.lookIsReady && !state.imageProcessing,
                        action: cubit.next,
                      ),
                    ],
            );
          case PublishStage.review:
            final names = cubit.names;
            // The upload review, as every other review with a cost: the
            // summary first, the names after, then the cost and how to pay.
            Widget review(BuildContext context) {
              final cost = state.cost!;
              // What is uploaded and paid for: the page, not the files.
              final size = cubit.uploadSize;
              return ChargedReviewDialog(
                title: title,
                destination: strings.publishStepOf(total, total),
                primaryLabel: strings.publishButton,
                busy: state.checkingWallet,
                // Whether the cost is covered is the review's to say, by the
                // method it shows; the cubit checks again with that method.
                // Here it only waits for the name step.
                primaryEnabled: names?.ready ?? true,
                onBack: cubit.back,
                leading: [
                  const SizedBox(height: ArDriveSpacing.md),
                  _Review(
                      state: state, scopeName: cubit.scopeName, names: names),
                ],
                extras: [
                  if (names != null) ArNSFlowNameSection(cubit: names),
                ],
                files: [
                  (
                    name: cubit.scopeName,
                    size: size,
                    contentType: 'text/html',
                  ),
                ],
                method: state.method,
                totalSize: size,
                costEstimateAr: cost.costEstimateAr,
                costEstimateTurbo:
                    cost.isTurboUploadPossible ? cost.costEstimateTurbo : null,
                turboBalance: cost.turboBalance,
                turboCredits: cost.turboCredits,
                arBalance: cost.arBalance,
                sufficientArBalance: cost.sufficientArBalance,
                freeStatus: cost.freeStatus,
                turboUnreachable: cost.turboUnreachable,
                onMethodChanged: cubit.setUploadMethod,
                refresh: cubit.refreshBalance,
                // The cubit refuses on its own what can't be paid for.
                onConfirm: (_) => cubit.publish(),
                onCancel: close,
              );
            }

            if (names == null) return review(context);
            // The button waits for the name step: priced, wallet ready.
            return BlocBuilder<ArNSNameDialogCubit, ArNSNameDialogState>(
              bloc: names,
              builder: (context, _) =>
                  BlocBuilder<ArNSWalletCubit, ArNSWalletState>(
                builder: (context, __) => review(context),
              ),
            );
          case PublishStage.publishing:
            // Close hides the dialog and the publish carries on; the app
            // says how it ended (see [showPublishSettledNotice]). There is no
            // Cancel: what was sent is paid for.
            return _modal(
              context,
              title: title,
              content: _Progress(
                state: state,
                names: cubit.names,
                // A private page has no snapshot: its catalog goes with the
                // page's own files.
                hasSnapshot: !cubit.isFile && !state.isPrivatePage,
              ),
              actions: [ModalAction.close(title: strings.close, action: close)],
            );
          case PublishStage.failed:
            return _modal(
              context,
              title: strings.publishFailedTitle,
              content: _Failed(state: state),
              actions: [
                ModalAction.close(title: strings.close, action: close),
                ModalAction.dismiss(
                    title: strings.publishBackToReview, action: cubit.back),
                if (state.canRetry)
                  ModalAction(
                      title: strings.publishTryAgain, action: cubit.retry),
              ],
            );
          case PublishStage.done:
            return _modal(
              context,
              title: state.method == UploadMethod.ar
                  ? strings.publishDoneArTitle
                  : strings.publishDoneTitle,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  PublishedLink(
                    link: state.link!,
                    isSecret: linkHasKey(state.link!),
                    note: [
                      if (linkHasKey(state.link!))
                        state.isPrivatePage
                            ? strings.publishPageKeyInLink
                            : strings.publishFileKeyInLink,
                      state.method == UploadMethod.ar
                          ? strings.publishDoneArNote
                          : strings.publishDoneNote,
                    ].join(' '),
                  ),
                  if (state.names != null && !state.names!.isEmpty) ...[
                    const SizedBox(height: 16),
                    ArNSFlowNameResult(outcome: state.names!),
                  ],
                ],
              ),
              actions: [
                ModalAction(
                  title: strings.publishOpenPage,
                  action: () => openUrl(url: state.link!),
                ),
                ModalAction(title: strings.doneEmphasized, action: close),
              ],
            );
        }
      },
    );
  }

  Widget _waiting(
    BuildContext context,
    String title,
    String text,
    VoidCallback close,
  ) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    return _modal(
      context,
      title: title,
      // The dialog's content column starts its children; the wait is
      // centred across the whole width.
      content: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ArDriveSpinner(size: ArDriveSpinnerSize.large),
            const SizedBox(height: ArDriveSpacing.sm),
            Text(text,
                textAlign: TextAlign.center,
                style: typography.paragraphNormal(color: colors.textMid)),
          ],
        ),
      ),
      actions: [
        ModalAction.close(
            title: appLocalizationsOf(context).cancel, action: close),
      ],
    );
  }
}

/// The look's width: the form beside the live previews.
const _lookWidth = 860.0;

Widget _modal(
  BuildContext context, {
  required String title,
  String? step,
  bool wide = false,
  required Widget content,
  required List<ModalAction> actions,
}) {
  final typography = ArDriveTypographyNew.of(context);
  final colors = ArDriveTheme.of(context).themeData.colorTokens;
  return ArDriveStandardModalNew(
    title: title,
    width: wide ? _lookWidth : kLargeDialogWidth,
    scrollableContent: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (step != null) ...[
          Text(step,
              style: typography.paragraphSmall(
                  color: colors.textLow, fontWeight: ArFontWeight.semiBold)),
          const SizedBox(height: 12),
        ],
        content,
      ],
    ),
    actions: actions,
  );
}

class _Blocked extends StatelessWidget {
  const _Blocked({required this.state});

  final PublishState state;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final isFile = context.read<PublishCubit>().isFile;
    final text = switch (state.blocked) {
      PublishBlock.pendingUploads => isFile
          ? strings.publishBlockedPendingFile
          : strings.publishBlockedPending(state.pendingChanges),
      PublishBlock.hiddenFolder => strings.publishBlockedHiddenFolder,
      PublishBlock.hiddenFile => strings.publishBlockedHiddenFile,
      PublishBlock.failedUpload => strings.publishBlockedFailedFile,
      PublishBlock.empty => strings.publishBlockedEmpty,
      PublishBlock.needsRelease => strings.publishHowNeedsRelease,
      PublishBlock.locked => strings.publishBlockedLocked,
      _ => state.blockedReason,
    };
    return Text(text,
        style: typography.paragraphNormal(color: colors.textHigh));
  }
}

/// A label and its value, as the snapshot dialog's summary shows them.
class SummaryRow extends StatelessWidget {
  const SummaryRow(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ArDriveSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label,
                style: typography.paragraphNormal(color: colors.textMid)),
          ),
          Expanded(
            child: Text(value,
                style: typography.paragraphNormal(
                    color: colors.textHigh, fontWeight: ArFontWeight.semiBold)),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ArDriveSpacing.sm),
      decoration: BoxDecoration(
        color: colors.containerL1,
        borderRadius: BorderRadius.circular(ArDriveRadius.md),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _Review extends StatelessWidget {
  const _Review({required this.state, required this.scopeName, this.names});

  final PublishState state;
  final String scopeName;

  /// The names that follow the page to its new version, on an update.
  final ArNSFlowNameCubit? names;

  String _updateLink(AppLocalizations strings) {
    final moving = names?.state.moving ?? const <ArNSNameRecord>[];
    if (moving.isEmpty) return strings.publishReviewUpdateLink;
    if (moving.length == 1) {
      return strings
          .publishReviewUpdateLinkName(arnsHostFor(moving.single.literalName));
    }
    return strings.publishReviewUpdateLinkNames(moving.length);
  }

  /// What the page will not show, and that anyone can find it: read here,
  /// with the cost, before anything is published.
  List<Widget> _leftOut(
    BuildContext context,
    AppLocalizations strings,
    PublicationSummary summary,
  ) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final leftOut = [
      if (summary.hiddenItems > 0)
        strings.publishLeftOutHidden(summary.hiddenItems),
      if (summary.inHiddenFolders > 0)
        strings.publishLeftOutInHidden(summary.inHiddenFolders),
      if (summary.inGhostFolders > 0)
        strings.publishLeftOutGhost(summary.inGhostFolders),
      if (summary.failedFiles > 0)
        strings.publishLeftOutFailed(summary.failedFiles),
    ];
    return [
      if (leftOut.isNotEmpty) ...[
        const SizedBox(height: ArDriveSpacing.md),
        Text(strings.publishLeftOut,
            style: typography.paragraphNormal(
                color: colors.textHigh, fontWeight: ArFontWeight.semiBold)),
        const SizedBox(height: ArDriveSpacing.xxs),
        for (final line in leftOut)
          Padding(
            padding: const EdgeInsets.only(top: ArDriveSpacing.xxs),
            child: Text('• $line',
                style: typography.paragraphNormal(color: colors.textMid)),
          ),
        // Hiding is not privacy: a public drive's data stays readable.
        // A private page leaves hidden items out with their keys.
        if (!state.isPrivatePage &&
            (summary.hiddenItems > 0 || summary.inHiddenFolders > 0)) ...[
          const SizedBox(height: ArDriveSpacing.xs),
          Text(strings.publishHiddenFindable,
              style: typography.paragraphSmall(color: colors.textMid)),
        ],
      ],
      const SizedBox(height: ArDriveSpacing.md),
      Text(
          state.isPrivatePage
              ? strings.publishPrivateIncludedNote
              : strings.publishIncludedNote,
          style: typography.paragraphSmall(color: colors.textLow)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final cubit = context.read<PublishCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Card(children: [
          SummaryRow(
              strings.publishReviewWhat,
              cubit.isFile
                  ? scopeName
                  : '$scopeName $arDriveSeparator ${strings.publishFileCount(state.summary!.fileCount)}'),
          if (!cubit.isFile)
            SummaryRow(strings.publishFolders, '${state.summary!.folderCount}'),
          SummaryRow(
              strings.publishTitleLabel,
              state.title.trim().isEmpty && state.isPrivatePage
                  ? strings.publicationPrivatePage
                  : state.title.trim()),
          if (state.isPrivatePage)
            SummaryRow(
              strings.publishReviewPassword,
              state.hasPassword || state.password.isNotEmpty
                  ? strings.publishReviewPasswordSet
                  : strings.publishReviewPasswordNone,
            ),
          SummaryRow(
            strings.publishReviewLink,
            state.isUpdate
                ? _updateLink(strings)
                : strings.publishReviewNewLink,
          ),
        ]),
        if (!cubit.isFile) ..._leftOut(context, strings, state.summary!),
        if (cubit.isPrivateFile || state.isPrivatePage) ...[
          const SizedBox(height: 12),
          Text(
              state.isPrivatePage
                  ? strings.publishReviewPrivatePage
                  : strings.publishReviewPrivateFile,
              style: typography.paragraphSmall(color: colors.textMid)),
        ],
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.state, this.names, this.hasSnapshot = true});

  final PublishState state;

  /// False for a file page, which has no snapshot to save.
  final bool hasSnapshot;

  /// The name step, whose wallet prompts show under the naming row.
  final ArNSFlowNameCubit? names;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final naming = state.naming;
    final steps = [
      if (hasSnapshot && !state.reusesSnapshot)
        (PublicationStep.snapshot, strings.publishStepSnapshot),
      (PublicationStep.files, strings.publishStepFiles),
      (PublicationStep.publication, strings.publishStepUpload),
      if (state.method == UploadMethod.turbo)
        (PublicationStep.warmUp, strings.publishStepWarmUp),
      // The names change last, once the page is up.
      if (naming.isNotEmpty)
        (
          null,
          naming.length == 1
              ? strings.publishStepName(naming.single)
              : strings.publishStepNames(naming.length),
        ),
    ];
    final current = state.step;
    final currentIndex = state.namingStarted
        ? steps.length - 1
        : current == null
            ? 0
            : steps.indexWhere((s) => s.$1 == current);
    Widget row(int i, String label) => Padding(
          padding: const EdgeInsets.symmetric(vertical: ArDriveSpacing.xs),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: i < currentIndex
                    ? ArDriveIcons.checkCirle(size: 20, color: colors.iconHigh)
                    : i == currentIndex
                        ? const Center(child: ArDriveSpinner())
                        : null,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(label,
                    style: typography.paragraphNormal(
                        color: i <= currentIndex
                            ? colors.textHigh
                            : colors.textLow)),
              ),
            ],
          ),
        );
    final nameCubit = names;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, (_, label)) in steps.indexed) row(i, label),
        // An ArNS wallet that has to approve the change says so, or the
        // dialog looks stuck while the prompt waits in the wallet.
        if (state.namingStarted && nameCubit != null)
          BlocBuilder<ArNSNameDialogCubit, ArNSNameDialogState>(
            bloc: nameCubit,
            builder: (context, nameState) {
              final prompt = switch (nameState.step) {
                ArNSCommitStep.approve => strings.arnsApproveInWallet,
                ArNSCommitStep.approveTransaction =>
                  strings.arnsApproveSecondPrompt,
                _ => null,
              };
              if (prompt == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(
                    left: ArDriveSpacing.xl, bottom: ArDriveSpacing.xs),
                child: Text(prompt,
                    style: typography.paragraphNormal(
                        color: colors.textHigh,
                        fontWeight: ArFontWeight.semiBold)),
              );
            },
          ),
        const SizedBox(height: 12),
        Text(strings.publishKeepOpen,
            style: typography.paragraphSmall(color: colors.textLow)),
      ],
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.state});

  final PublishState state;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ArDriveNotice(
          type: ArDriveNoticeType.error,
          message: state.failure,
        ),
        if (state.paidTxId != null) ...[
          const SizedBox(height: 12),
          Text.rich(TextSpan(
            style: typography.paragraphSmall(color: colors.textMid),
            children: ArDriveIdText.spansIn(
              // Whole: the owner may need it to look the payment up.
              strings.publishPaidNote(state.paidTxId!),
              state.paidTxId!,
              idStyle: typography.code(color: colors.textMid, fontSize: 11),
            ),
          )),
        ],
      ],
    );
  }
}

/// A publication's link, in the read-only field and Copy link that sharing
/// uses, with an optional note under it.
class PublishedLink extends StatelessWidget {
  const PublishedLink({
    super.key,
    required this.link,
    this.note,
    this.isSecret = false,
  });

  final String link;
  final String? note;

  /// A private file page's link, which carries the file's key.
  final bool isSecret;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CopyableShareArtifact(
          label: strings.shareFileLinkLabel,
          text: link,
          copyLabel: strings.copyLink,
          revealLabel: strings.shareFileRevealKey,
          isSecret: isSecret,
        ),
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(note!, style: typography.paragraphSmall(color: colors.textLow)),
        ],
      ],
    );
  }
}

/// A file's first step: its page, or the file itself.
class _How extends StatelessWidget {
  const _How({required this.state});

  final PublishState state;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final cubit = context.read<PublishCubit>();
    final private = cubit.isPrivateFile;
    final pageNote = switch (state.filePages) {
      FilePageAvailability.needsRelease => strings.publishHowNeedsRelease,
      FilePageAvailability.unknown => strings.publishHowUnknown,
      _ => private
          ? strings.publishHowPagePrivateNote
          : strings.publishHowPageNote,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings.publishHowLabel,
            style: typography.heading5(fontWeight: ArFontWeight.bold)),
        const SizedBox(height: 4),
        Text(cubit.scopeName,
            style: typography.paragraphNormal(color: colors.textMid)),
        const SizedBox(height: 16),
        // One bordered group, a row per choice, as the payment choice is.
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ArDriveRadius.lg),
            border: Border.all(color: colors.strokeMid),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HowOption(
                title: strings.publishHowPage,
                note: pageNote,
                isSelected: state.how == FilePublishHow.page,
                reservesCheck: true,
                isChecking: state.how == FilePublishHow.page &&
                    state.filePages == FilePageAvailability.checking,
                onTap: () {
                  cubit.setHow(FilePublishHow.page);
                  cubit.retryFilePages();
                },
              ),
              Divider(height: 1, color: colors.strokeMid),
              _HowOption(
                title: strings.publishHowItself,
                note: private
                    ? strings.publishHowItselfPrivate
                    : strings.publishHowItselfNote,
                isSelected: state.how == FilePublishHow.itself,
                onTap:
                    private ? null : () => cubit.setHow(FilePublishHow.itself),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HowOption extends StatelessWidget {
  const _HowOption({
    required this.title,
    required this.note,
    required this.isSelected,
    required this.onTap,
    this.isChecking = false,
    this.reservesCheck = false,
  });

  final String title;
  final String note;
  final bool isSelected;

  /// Null when this choice is off.
  final VoidCallback? onTap;

  /// Whether this choice is still being checked.
  final bool isChecking;

  /// Whether the spinner's slot is kept while not checking, so the note does
  /// not rewrap when the check starts or ends.
  final bool reservesCheck;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final enabled = onTap != null;
    final dot = isSelected ? colors.textHigh : colors.strokeHigh;
    return Semantics(
      button: true,
      enabled: enabled,
      inMutuallyExclusiveGroup: true,
      selected: isSelected,
      child: Material(
        color: isSelected ? colors.buttonSecondaryDefault : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Opacity(
            opacity: enabled ? 1 : 0.5,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: ArDriveSpacing.md, vertical: ArDriveSpacing.sm),
              child: Row(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: dot, width: 2),
                    ),
                    child: isSelected
                        ? Center(
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle, color: dot),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: typography.paragraphNormal(
                                fontWeight: ArFontWeight.semiBold,
                                color: colors.textHigh)),
                        Text(note,
                            style: typography.paragraphSmall(
                                color: colors.textMid)),
                      ],
                    ),
                  ),
                  if (isChecking || reservesCheck) ...[
                    const SizedBox(width: 12),
                    SizedBox.square(
                      dimension: 16,
                      child: isChecking ? const ArDriveSpinner() : null,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The file itself: its permanent link, and a name for it.
class _Itself extends StatelessWidget {
  const _Itself({required this.link, required this.file});

  final String link;
  final FileEntry file;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final names = arnsNamesOn(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(strings.publishHowItself,
            style: typography.heading5(fontWeight: ArFontWeight.bold)),
        const SizedBox(height: 4),
        Text(file.name,
            style: typography.paragraphNormal(color: colors.textMid)),
        const SizedBox(height: 16),
        PublishedLink(link: link, note: strings.publishItselfNote),
        if (names) ...[
          const SizedBox(height: ArDriveSpacing.lg),
          Text(strings.publishItselfNameNote,
              style: typography.paragraphSmall(color: colors.textMid)),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: BlocBuilder<ArNSNamesCubit, ArNSNamesState>(
              builder: (context, namesState) {
                final named = namesState.recordsFor(file.dataTxId).isNotEmpty;
                final label =
                    named ? strings.arnsChangeName : strings.arnsAddName;
                return publishButton(
                  context,
                  label,
                  onPressed: () => showArNSNameDialog(
                    context,
                    mode: ArNSNameDialogMode.nameItem,
                    item: ArNSNameableItem(
                      fileId: file.id,
                      driveId: file.driveId,
                      name: file.name,
                      dataTxId: file.dataTxId,
                      isManifest: file.dataContentType == ContentType.manifest,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// Puts the dialog's scroll back where it was when [child] shows something
/// else in place of its content for a while, such as a chooser.
///
/// The content behind stays mounted, but the dialog's one scroll view
/// clamps to the shorter thing shown instead, so its offset is lost unless
/// it is kept here.
@visibleForTesting
class KeepsScrollWhileAway extends StatefulWidget {
  const KeepsScrollWhileAway({
    super.key,
    required this.away,
    required this.child,
  });

  /// Something else is shown in place of the content.
  final bool away;
  final Widget child;

  @override
  State<KeepsScrollWhileAway> createState() => _KeepsScrollWhileAwayState();
}

class _KeepsScrollWhileAwayState extends State<KeepsScrollWhileAway> {
  double? _saved;

  @override
  void didUpdateWidget(KeepsScrollWhileAway oldWidget) {
    super.didUpdateWidget(oldWidget);
    final position = Scrollable.maybeOf(context)?.position;
    if (position == null) return;
    if (!oldWidget.away && widget.away) {
      _saved = position.pixels;
      return;
    }
    final saved = _saved;
    if (oldWidget.away && !widget.away && saved != null) {
      _saved = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !position.hasPixels) return;
        position.jumpTo(
            saved.clamp(position.minScrollExtent, position.maxScrollExtent));
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

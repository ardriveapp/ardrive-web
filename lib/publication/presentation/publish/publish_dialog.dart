import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog_cubit.dart';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/components/copyable_share_artifact.dart';
import 'package:ardrive/components/payment_method_selector_widget.dart';
import 'package:ardrive/components/turbo_free_status_message.dart';
import 'package:ardrive/drive_state/data/arweave_drive_state_uploader.dart';
import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/domain/drive_state_creation_service.dart';
import 'package:ardrive/drive_state/domain/drive_state_publish_cost.dart';
import 'package:ardrive/drive_state/domain/drive_state_sync_skip_status.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/publication/data/publication_repository.dart';
import 'package:ardrive/publication/data/publication_uploader.dart';
import 'package:ardrive/publication/domain/publication_publisher.dart';
import 'package:ardrive/publication/presentation/publications_cubit.dart';
import 'package:ardrive/publication/presentation/publish/publish_cubit.dart';
import 'package:ardrive/publication/presentation/publish/publish_look_step.dart';
import 'package:ardrive/publication/presentation/publish/published_view.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart' show TabVisibilitySingleton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:pst/pst.dart';

/// "Publish to web" on a drive ([folder] null) or a folder: the published
/// view when it is published already, else the publish dialog
/// (docs/PUBLICATIONS.md, "Entry points").
Future<void> promptToPublish(
  BuildContext context, {
  required Drive drive,
  FolderEntry? folder,
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
          ModalAction.dismiss(
            title: strings.close,
            action: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
  final publication = known.of(folder?.id);
  if (publication != null) {
    return showPublishedView(
      context,
      drive: drive,
      folder: folder,
      publication: publication,
    );
  }
  return showPublishDialog(context, drive: drive, folder: folder);
}

/// The publish dialog. [previous] makes it an update of that publication,
/// opening on the look.
Future<void> showPublishDialog(
  BuildContext context, {
  required Drive drive,
  FolderEntry? folder,
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
    ),
    cardMark: () => loadAssetImage(Resources.images.brand.logo1),
    fileCountLabel: strings.publishFileCount,
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
  final colors = ArDriveTheme.of(messenger.context).themeData.colorTokens;
  messenger.showSnackBar(
    SnackBar(
      // Typography reads the screen width, known where the snackbar shows.
      content: Builder(
        builder: (context) => Text(
          link != null
              ? strings.publishDoneTitle
              : strings.publishStoppedNotice,
          style: ArDriveTypographyNew.of(context)
              .paragraphNormal(color: colors.textHigh),
        ),
      ),
      backgroundColor: colors.containerL3,
      duration: const Duration(seconds: 10),
      action: link == null
          ? null
          : SnackBarAction(
              label: strings.publishOpen,
              backgroundColor: colors.containerL3,
              textColor: colors.textHigh,
              onPressed: () => openUrl(url: link),
            ),
    ),
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

        switch (state.stage) {
          case PublishStage.loading:
            return _waiting(context, title, strings.publishGettingReady, close);
          case PublishStage.pricing:
            return _waiting(
                context, title, strings.publishWorkingOutCost, close);
          case PublishStage.blocked:
            return _modal(
              context,
              title: title,
              content: _Blocked(state: state),
              actions: [
                ModalAction.dismiss(title: strings.close, action: close)
              ],
            );
          case PublishStage.included:
            return _modal(
              context,
              title: title,
              step: strings.publishStepOf(1, 3),
              content: _Included(
                  state: state,
                  scopeName: cubit.scopeName,
                  isFolder: cubit.folder != null),
              actions: [
                ModalAction(title: strings.cancel, action: close),
                ModalAction(title: strings.next, action: cubit.next),
              ],
            );
          case PublishStage.look:
            return _modal(
              context,
              title: title,
              step: strings.publishStepOf(2, 3),
              wide: true,
              content: const PublishLookStep(),
              actions: [
                ModalAction(title: strings.back, action: cubit.back),
                ModalAction(
                  title: strings.next,
                  isEnable: state.titleIsValid,
                  action: cubit.next,
                ),
              ],
            );
          case PublishStage.review:
            final names = cubit.names;
            Widget review(BuildContext context) => _modal(
                  context,
                  title: title,
                  step: strings.publishStepOf(3, 3),
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Review(state: state, scopeName: cubit.scopeName),
                      if (names != null) ...[
                        const SizedBox(height: 16),
                        ArNSFlowNameSection(cubit: names),
                      ],
                    ],
                  ),
                  actions: [
                    ModalAction(title: strings.back, action: cubit.back),
                    ModalAction(
                      title: strings.publishButton,
                      isEnable: state.canPublish && (names?.ready ?? true),
                      action: cubit.publish,
                    ),
                  ],
                );
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
              content: _Progress(state: state),
              actions: [
                ModalAction.dismiss(title: strings.close, action: close)
              ],
            );
          case PublishStage.failed:
            return _modal(
              context,
              title: strings.publishFailedTitle,
              content: _Failed(state: state),
              actions: [
                ModalAction(title: strings.close, action: close),
                ModalAction(
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
                    note: state.method == UploadMethod.ar
                        ? strings.publishDoneArNote
                        : strings.publishDoneNote,
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
      content: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: typography.paragraphNormal(color: colors.textMid)),
          ),
        ],
      ),
      actions: [
        ModalAction.dismiss(
            title: appLocalizationsOf(context).cancel, action: close),
      ],
    );
  }
}

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
    width: wide ? 860 : 520,
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
    final text = switch (state.blocked) {
      PublishBlock.pendingUploads => strings.publishBlockedPending,
      PublishBlock.hiddenFolder => strings.publishBlockedHiddenFolder,
      PublishBlock.empty => strings.publishBlockedEmpty,
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
      padding: const EdgeInsets.symmetric(vertical: 4),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.containerL1,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _Included extends StatelessWidget {
  const _Included({
    required this.state,
    required this.scopeName,
    required this.isFolder,
  });

  final PublishState state;
  final String scopeName;
  final bool isFolder;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final summary = state.summary!;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings.publishWhatsIncluded,
            style: typography.heading5(fontWeight: ArFontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          '${isFolder ? strings.publishScopeFolder : strings.publishScopeDrive} • $scopeName',
          style: typography.paragraphNormal(color: colors.textMid),
        ),
        const SizedBox(height: 16),
        _Card(children: [
          SummaryRow(strings.publishFiles, '${summary.fileCount}'),
          SummaryRow(strings.publishFolders, '${summary.folderCount}'),
          SummaryRow(strings.publishSize, filesize(summary.totalSize)),
        ]),
        if (leftOut.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(strings.publishLeftOut,
              style: typography.paragraphNormal(
                  color: colors.textHigh, fontWeight: ArFontWeight.semiBold)),
          const SizedBox(height: 4),
          for (final line in leftOut)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('• $line',
                  style: typography.paragraphNormal(color: colors.textMid)),
            ),
          // Hiding is not privacy: a public drive's data stays readable.
          if (summary.hiddenItems > 0 || summary.inHiddenFolders > 0) ...[
            const SizedBox(height: 8),
            Text(strings.publishHiddenFindable,
                style: typography.paragraphSmall(color: colors.textMid)),
          ],
        ],
        const SizedBox(height: 16),
        Text(strings.publishIncludedNote,
            style: typography.paragraphSmall(color: colors.textLow)),
      ],
    );
  }
}

class _Review extends StatelessWidget {
  const _Review({required this.state, required this.scopeName});

  final PublishState state;
  final String scopeName;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final cubit = context.read<PublishCubit>();
    final cost = state.cost!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings.publishReview,
            style: typography.heading5(fontWeight: ArFontWeight.bold)),
        const SizedBox(height: 16),
        _Card(children: [
          SummaryRow(strings.publishReviewWhat,
              '$scopeName • ${strings.publishFileCount(state.summary!.fileCount)}'),
          SummaryRow(strings.publishTitleLabel, state.title.trim()),
          SummaryRow(
            strings.publishReviewLink,
            state.isUpdate
                ? strings.publishReviewUpdateLink
                : strings.publishReviewNewLink,
          ),
        ]),
        const SizedBox(height: 16),
        TurboFreeStatusMessage(
          status: cost.freeStatus,
          padding: const EdgeInsets.only(bottom: 12),
        ),
        if (!cost.isFree)
          PaymentMethodSelector(
            uploadMethodInfo: UploadPaymentMethodInfo(
              uploadMethod: state.method,
              totalSize: 0,
              costEstimateAr: cost.costEstimateAr,
              costEstimateTurbo: cost.costEstimateTurbo,
              hasNoTurboBalance: cost.hasNoTurboBalance,
              isTurboUploadPossible: cost.isTurboUploadPossible,
              arBalance: cost.arBalance,
              sufficientArBalance: cost.sufficientArBalance,
              turboCredits: cost.turboCredits,
              sufficentCreditsBalance: cost.sufficientTurboBalance,
              freeStatus: FreeUploadStatus.notEligible,
            ),
            onTurboTopupSucess: cubit.refreshBalance,
            onArSelect: () => cubit.setUploadMethod(UploadMethod.ar),
            onTurboSelect: () => cubit.setUploadMethod(UploadMethod.turbo),
          ),
        if (state.method == UploadMethod.ar && !cost.isFree) ...[
          const SizedBox(height: 8),
          Text(strings.publishArNote,
              style: typography.paragraphSmall(color: colors.textMid)),
        ],
        if (cost.isUnaffordable) ...[
          const SizedBox(height: 8),
          Text(strings.publishUnaffordable,
              style: typography.paragraphSmall(color: colors.textRed)),
        ],
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ArDriveIcons.triangle(size: 16, color: colors.iconMid),
            const SizedBox(width: 8),
            Expanded(
              child: Text(strings.publishPermanent,
                  style: typography.paragraphNormal(
                      color: colors.textHigh,
                      fontWeight: ArFontWeight.semiBold)),
            ),
          ],
        ),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.state});

  final PublishState state;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final steps = [
      if (!state.reusesSnapshot)
        (PublicationStep.snapshot, strings.publishStepSnapshot),
      (PublicationStep.files, strings.publishStepFiles),
      (PublicationStep.publication, strings.publishStepUpload),
      if (state.method == UploadMethod.turbo)
        (PublicationStep.warmUp, strings.publishStepWarmUp),
    ];
    final current = state.step;
    final currentIndex =
        current == null ? 0 : steps.indexWhere((s) => s.$1 == current);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, (_, label)) in steps.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: i < currentIndex
                      ? ArDriveIcons.checkCirle(
                          size: 20, color: colors.iconHigh)
                      : i == currentIndex
                          ? const CircularProgressIndicator(strokeWidth: 2)
                          : null,
                ),
                const SizedBox(width: 12),
                Text(label,
                    style: typography.paragraphNormal(
                        color: i <= currentIndex
                            ? colors.textHigh
                            : colors.textLow)),
              ],
            ),
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
        Text(state.failure,
            style: typography.paragraphNormal(color: colors.textHigh)),
        if (state.paidTxId != null) ...[
          const SizedBox(height: 12),
          Text(strings.publishPaidNote(state.paidTxId!),
              style: typography.paragraphSmall(color: colors.textMid)),
        ],
      ],
    );
  }
}

/// A publication's link, in the read-only field and Copy link that sharing
/// uses, with an optional note under it.
class PublishedLink extends StatelessWidget {
  const PublishedLink({super.key, required this.link, this.note});

  final String link;
  final String? note;

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
          // Never shown: a publication's link carries no key.
          revealLabel: strings.copyLink,
        ),
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(note!, style: typography.paragraphSmall(color: colors.textLow)),
        ],
      ],
    );
  }
}

import 'dart:math';

import 'package:ardrive/pages/raw_transaction_view/raw_transaction_preview.dart';
import 'package:ardrive/pages/raw_transaction_view/raw_transaction_view_cubit.dart';
// The recipient landing page's chrome, card and states. `/view` is the same
// page for a reader who was sent a link, so it is the same frame, the same
// ready card and the same error states - see
// `docs/FILE_SHARING_REDESIGN_PLAN.md` §2, which specifies one state machine
// for both routes.
import 'package:ardrive/pages/shared_file/shared_file_frame.dart';
import 'package:ardrive/pages/shared_file/shared_file_identity.dart';
import 'package:ardrive/pages/shared_file/shared_file_ready_layout.dart';
import 'package:ardrive/pages/shared_file/shared_file_ready_view.dart'
    show SharedFileDetailRow, SharedFileDrawer, SharedFileInfoPanel;
import 'package:ardrive/pages/shared_file/shared_file_status_views.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

/// `/view/{txId}` - ArDrive as a front end for any Arweave transaction.
///
/// Somebody is handed a transaction id and, instead of a raw gateway URL that
/// downloads an unnamed blob or renders who-knows-what, gets a page with a
/// name, a preview and a download button. That is the whole product argument
/// for sending an app link rather than a gateway link, and it only holds if the
/// page is safe to open, which is what
/// `docs/FILE_SHARING_REDESIGN_PLAN.md` §4.3 is about.
///
/// v1 of this route serves **public content only**: it accepts `n` and `ct`
/// hints and nothing else, so an encrypted blob with no ArFS context around it
/// arrives here as bytes nobody can read and renders as the download-only card
/// (§1.3).
class RawTransactionViewPage extends StatelessWidget {
  const RawTransactionViewPage({
    super.key,
    required this.txId,
    this.name,
    this.contentType,
  });

  /// The transaction to show. Arbitrary, attacker-chosen, and validated for
  /// shape before anything at all is done with it.
  final String txId;

  /// The link's `n` hint - a name to show while the network answers.
  final String? name;

  /// The link's `ct` hint. A claim, weighed with the transaction's own tag and
  /// the gateway's header, and never able to unlock a renderer on its own.
  final String? contentType;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<RawTransactionViewCubit>(
      key: ValueKey(txId),
      create: (context) => RawTransactionViewCubit(
        txId: txId,
        arweave: context.read<ArweaveService>(),
        nameHint: name,
        contentTypeHint: contentType,
      ),
      child: const RawTransactionViewBody(),
    );
  }
}

/// The page's state machine, split from [RawTransactionViewPage] so that it can
/// be driven by a mocked cubit in a widget test - the same split the recipient
/// page uses.
class RawTransactionViewBody extends StatelessWidget {
  const RawTransactionViewBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      child: BlocBuilder<RawTransactionViewCubit, RawTransactionViewState>(
        // The same fork the recipient page makes, at the same breakpoint.
        // `tablet` is deliberately not supplied: the package falls back to
        // `mobile` for 600-950px, and a 700px window is a reading column, not
        // half a desktop.
        builder: (context, state) => ScreenTypeLayout.builder(
          mobile: (context) => _buildFrame(context, state, isWide: false),
          desktop: (context) => _buildFrame(context, state, isWide: true),
        ),
      ),
    );
  }

  /// The frame, sized for the state inside it.
  ///
  /// As on the recipient page, only the ready card has any use for the extra
  /// width - it is the one that hosts the preview. The spinner and the error
  /// cards read better narrow and stay narrow at every screen size.
  Widget _buildFrame(
    BuildContext context,
    RawTransactionViewState state, {
    required bool isWide,
  }) {
    final isWideReady = isWide && state is RawTransactionReady;

    return SharedFileFrame(
      maxWidth: isWideReady
          ? SharedFileFrame.maxWideContentWidth
          : SharedFileFrame.maxContentWidth,
      child: _buildState(context, state, isWide: isWideReady),
    );
  }

  Widget _buildState(
    BuildContext context,
    RawTransactionViewState state, {
    required bool isWide,
  }) {
    if (state is RawTransactionReady) {
      return RawTransactionReadyView(state: state, isWide: isWide);
    }

    if (state is RawTransactionLinkDamaged) {
      return SharedFileMessage(
        icon: ArDriveIcons.fileX(
          size: 32,
          color: ArDriveTheme.of(context).themeData.colors.themeFgSubtle,
        ),
        message: appLocalizationsOf(context).rawTransactionLinkDamaged,
      );
    }

    if (state is RawTransactionNotFound) {
      return SharedFileMessage(
        icon: ArDriveIcons.fileX(
          size: 32,
          color: ArDriveTheme.of(context).themeData.colors.themeFgSubtle,
        ),
        message: appLocalizationsOf(context).rawTransactionNotFoundOnNetwork,
        actionLabel: appLocalizationsOf(context).sharedFileRetry,
        onAction: () => context.read<RawTransactionViewCubit>().retry(),
      );
    }

    if (state is RawTransactionLoadFailure) {
      // Reused verbatim: the copy is about the network, not about ArFS.
      return SharedFileNetworkErrorView(
        onRetry: () => context.read<RawTransactionViewCubit>().retry(),
      );
    }

    final loading = state is RawTransactionLoadInProgress ? state : null;

    return _RawTransactionResolvingView(
      name: loading?.name,
      contentType: loading?.contentType,
    );
  }
}

/// RESOLVING, with whatever the link already told us.
///
/// Not [SharedFileResolvingView]: that one takes a `SharedFileLinkPayload`,
/// which is a *share link's* payload and has no business describing a raw
/// transaction. The substance - the identity card and the copy - is shared.
class _RawTransactionResolvingView extends StatelessWidget {
  const _RawTransactionResolvingView({this.name, this.contentType});

  final String? name;
  final String? contentType;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SharedFileIdentity(
          name: name,
          contentType: contentType,
          isLoading: true,
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                appLocalizationsOf(context).sharedFileLoadingDetails,
                style: ArDriveTypography.body.captionRegular(
                  color: colors.themeFgSubtle,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// READY - what the transaction is, what it looks like, and how to keep it, in
/// the recipient page's own card ([SharedFileReadyLayout]).
///
/// Public for its widget tests, which drive both layouts directly.
class RawTransactionReadyView extends StatefulWidget {
  const RawTransactionReadyView({
    super.key,
    required this.state,
    this.isWide = false,
    this.preview,
  });

  final RawTransactionReady state;

  /// Whether there is room for the preview pane. Decided by the page, from the
  /// screen size, so that the frame's width and this layout always agree.
  final bool isWide;

  /// Injectable for tests; otherwise the real [RawTransactionPreview], whose
  /// PDF and media renderers need a browser.
  final Widget? preview;

  @override
  State<RawTransactionReadyView> createState() =>
      _RawTransactionReadyViewState();
}

/// The preview pane on the wide card, which a widget test measures.
@visibleForTesting
const Key rawTransactionPreviewPaneKey = Key('rawTransactionPreviewPane');

class _RawTransactionReadyViewState extends State<RawTransactionReadyView> {
  /// Room between the pane's border and what is in it.
  static const double _paneInset = 16;

  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final isWide = widget.isWide;
    final preview = widget.preview ?? RawTransactionPreview(state: state);

    return SharedFileReadyLayout(
      isWide: isWide,
      identity: SharedFileIdentity(
        // A transaction with no name hint and no naming tag is exactly what it
        // is, and saying so beats the share page's "Shared file" - nobody
        // shared a *file* here.
        name: state.name ??
            appLocalizationsOf(context).rawTransactionGenericTitle,
        size: state.size,
        contentType: state.presentation.contentType,
        ownerAddress: state.ownerAddress,
      ),
      download: ArDriveButton(
        maxWidth: isWide ? null : double.infinity,
        isDisabled: _isSaving,
        icon: ArDriveIcons.download(size: 20, color: Colors.white),
        onPressed: _download,
        text: appLocalizationsOf(context).download,
      ),
      // Always something to show: the preview widget renders every
      // presentation, including the ones that are only a sentence and an offer
      // to open the transaction elsewhere.
      inlinePreview: preview,
      previewPaneKey: rawTransactionPreviewPaneKey,
      previewPane: _buildPane(preview),
      infoPanel: (height) => SharedFileInfoPanel(
        height: height,
        details: RawTransactionDetailsContent(state: state),
      ),
    );
  }

  /// The preview, fitted to the wide card's fixed pane.
  ///
  /// The pane's height is fixed so nothing moves under the pointer, and the
  /// preview is a column whose height the transaction decides: a warning that
  /// the type was contradicted, a note that it is sandboxed, up to 360px of
  /// content, and an offer to open it on the gateway. Every one of those can
  /// be present at once. So the pane scrolls rather than clip or overflow, and
  /// anything shorter than the pane sits in its middle, the way the recipient
  /// page's pane centres its preview.
  Widget _buildPane(Widget preview) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(_paneInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: max(0, constraints.maxHeight - 2 * _paneInset),
          ),
          child: Center(child: preview),
        ),
      ),
    );
  }

  /// Saves the bytes this page already holds, or - when it holds none, because
  /// the transaction streams or was too big to look at - hands the browser the
  /// gateway's per-transaction origin and lets it do the fetching.
  Future<void> _download() async {
    final state = widget.state;
    final bytes = state.bytes;

    setState(() => _isSaving = true);

    try {
      if (bytes == null) {
        await openUrl(url: state.sandboxUrl, webOnlyWindowName: '_blank');

        return;
      }

      await ArDriveIO().saveFile(
        await IOFile.fromData(
          bytes,
          // The transaction id is a perfectly good name for a thing that never
          // had one, and it is the one string here that is guaranteed safe.
          name: state.name ?? state.txId,
          lastModifiedDate: DateTime.now(),
          contentType: state.presentation.contentType,
        ),
      );
    } catch (e) {
      logger.e('Could not save transaction ${state.txId}', e);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              appLocalizationsOf(context).rawTransactionDownloadFailed,
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}

/// The Details tab for a bare transaction, in the recipient page's rows.
///
/// What a person can use leads - the type, and who put it on the network - and
/// the identifier waits one step further in, behind the same disclosure the
/// share page uses, for the same reason: somebody should be able to get the
/// thing without ever learning what a transaction id is.
///
/// Public for its widget tests.
class RawTransactionDetailsContent extends StatelessWidget {
  const RawTransactionDetailsContent({super.key, required this.state});

  final RawTransactionReady state;

  @override
  Widget build(BuildContext context) {
    final contentType = state.presentation.contentType;
    final ownerAddress = state.ownerAddress;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (contentType != null && contentType.isNotEmpty)
          SharedFileDetailRow(
            label: appLocalizationsOf(context).fileType,
            value: contentType,
            canCopy: false,
          ),
        if (ownerAddress != null && ownerAddress.isNotEmpty)
          SharedFileDetailRow(
            label: appLocalizationsOf(context).sharedFileDetailsOwner,
            value: ownerAddress,
          ),
        SharedFileDrawer(
          title: appLocalizationsOf(context).sharedFileTransactionDetails,
          children: [
            SharedFileDetailRow(
              label: appLocalizationsOf(context).sharedFileDetailsTransaction,
              value: state.txId,
            ),
          ],
        ),
      ],
    );
  }
}

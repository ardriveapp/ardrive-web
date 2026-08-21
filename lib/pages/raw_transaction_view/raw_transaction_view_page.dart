import 'package:ardrive/pages/raw_transaction_view/raw_transaction_preview.dart';
import 'package:ardrive/pages/raw_transaction_view/raw_transaction_view_cubit.dart';
// The recipient landing page's chrome and identity card. `/view` is the same
// page for a reader who was sent a link, so it is the same frame, the same card
// and the same error states - see `docs/FILE_SHARING_REDESIGN_PLAN.md` §2,
// which specifies one state machine for both routes.
import 'package:ardrive/pages/shared_file/shared_file_frame.dart';
import 'package:ardrive/pages/shared_file/shared_file_identity.dart';
import 'package:ardrive/pages/shared_file/shared_file_status_views.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
        builder: (context, state) => SharedFileFrame(
          child: _buildState(context, state),
        ),
      ),
    );
  }

  Widget _buildState(BuildContext context, RawTransactionViewState state) {
    if (state is RawTransactionReady) {
      return _RawTransactionReadyView(state: state);
    }

    if (state is RawTransactionLinkDamaged) {
      return _RawTransactionMessage(
        icon: ArDriveIcons.fileX(
          size: 32,
          color: ArDriveTheme.of(context).themeData.colors.themeFgSubtle,
        ),
        message: appLocalizationsOf(context).rawTransactionLinkDamaged,
      );
    }

    if (state is RawTransactionNotFound) {
      return _RawTransactionMessage(
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

    final loading =
        state is RawTransactionLoadInProgress ? state : null;

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

/// READY - what the transaction is, what it looks like, and how to keep it.
class _RawTransactionReadyView extends StatefulWidget {
  const _RawTransactionReadyView({required this.state});

  final RawTransactionReady state;

  @override
  State<_RawTransactionReadyView> createState() =>
      _RawTransactionReadyViewState();
}

class _RawTransactionReadyViewState extends State<_RawTransactionReadyView> {
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SharedFileIdentity(
          name: state.name,
          size: state.size,
          contentType: state.presentation.contentType,
          ownerAddress: state.ownerAddress,
        ),
        const SizedBox(height: 20),
        ArDriveButton(
          maxWidth: double.infinity,
          isDisabled: _isSaving,
          icon: ArDriveIcons.download(size: 20, color: Colors.white),
          onPressed: _download,
          text: appLocalizationsOf(context).download,
        ),
        const SizedBox(height: 12),
        RawTransactionPreview(state: state),
        const SizedBox(height: 16),
        _RawTransactionDetailsDrawer(state: state),
      ],
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

/// Where the protocol lives, one deliberate tap away.
///
/// Mirrors `SharedFileDetailsContent`, whose row and drawer helpers are private
/// to `shared_file_ready_view.dart` and are built around a `FileRevision` that a
/// raw transaction does not have. Extracting them would mean reshaping the
/// recipient page's ready view around a second caller for two rows; this copy
/// is the smaller change.
class _RawTransactionDetailsDrawer extends StatelessWidget {
  const _RawTransactionDetailsDrawer({required this.state});

  final RawTransactionReady state;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final ownerAddress = state.ownerAddress;

    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(
          appLocalizationsOf(context).sharedFileDetailsDrawerTitle,
          style: ArDriveTypography.body.captionBold(
            color: colors.themeFgSubtle,
          ),
        ),
        children: [
          _RawTransactionDetailRow(
            label: appLocalizationsOf(context).sharedFileDetailsTransaction,
            value: state.txId,
          ),
          if (ownerAddress != null && ownerAddress.isNotEmpty)
            _RawTransactionDetailRow(
              label: appLocalizationsOf(context).sharedFileDetailsOwner,
              value: ownerAddress,
            ),
        ],
      ),
    );
  }
}

class _RawTransactionDetailRow extends StatelessWidget {
  const _RawTransactionDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: ArDriveTypography.body.captionRegular(
                color: colors.themeFgSubtle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: ArDriveTypography.body.captionRegular(
                color: colors.themeFgDefault,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ArDriveTooltip(
            message: appLocalizationsOf(context).copyTooltip,
            child: GestureDetector(
              onTap: () => Clipboard.setData(ClipboardData(text: value)),
              child: ArDriveClickArea(
                child: ArDriveIcons.copy(size: 16, color: colors.themeFgSubtle),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An icon, a sentence and at most one thing to do about it.
///
/// The same shape as `_SharedFileMessage`, which is private to
/// `shared_file_status_views.dart`. Copied rather than extracted because
/// exporting it would mean reworking that file's four public views around a
/// shared base for the sake of two states.
class _RawTransactionMessage extends StatelessWidget {
  const _RawTransactionMessage({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final Widget icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final actionLabel = this.actionLabel;
    final onAction = this.onAction;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(child: icon),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: ArDriveTypography.body.bodyRegular(
            color: colors.themeFgDefault,
          ),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 24),
          ArDriveButton(
            maxWidth: double.infinity,
            onPressed: onAction,
            text: actionLabel,
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/fs_entry_preview/fs_entry_preview_cubit.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
// The preview widget is a part of the drive detail library; `show` keeps the
// rest of that very large surface out of this file.
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart'
    show FsEntryPreviewWidget;
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/pages/shared_file/shared_file_identity.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/file_revision_base.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/format_date.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The ready card: what the recipient came for, in the order they want it.
///
/// Name and size first, one obvious Download, an optional preview, and every
/// transaction id folded away in the details drawer (review F18). A recipient
/// should be able to get their file without ever learning what a transaction
/// id is.
///
/// On the v2 fast path this card paints before the file's metadata has been
/// read, so anything the link did not carry
/// ([SharedFileLoadSuccess.detailsAreResolved] `== false`) is a placeholder
/// here - an empty name, a zero size - and is rendered as *unknown* rather than
/// as a wrong value.
class SharedFileReadyView extends StatefulWidget {
  const SharedFileReadyView({super.key, required this.state});

  final SharedFileLoadSuccess state;

  @override
  State<SharedFileReadyView> createState() => _SharedFileReadyViewState();
}

class _SharedFileReadyViewState extends State<SharedFileReadyView> {
  bool _isPreviewOpen = false;

  /// Whether a download is in flight.
  ///
  /// The target must not move while bytes are being fetched (decision 1:
  /// offer, never swap), so while this is set the page will not offer to change
  /// it. Today the download dialog is a modal barrier and nothing underneath it
  /// can be pressed anyway; in Phase 2 the progress moves onto the button
  /// itself (§2, `DOWNLOADING`) and this becomes the only thing standing
  /// between a running download and a swapped target.
  bool _isDownloading = false;

  /// Whether the resolver is fetching the revision the recipient asked for.
  bool _isChangingRevision = false;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final state = widget.state;
    final payload = state.payload;

    // What the page shows and downloads: the revision the link points at,
    // unless the recipient has pressed for the newest one. It never moves on
    // its own - the banner offers, and only a press takes the offer.
    final revision = state.revision;

    // Nothing may move the target while bytes are on their way, and nothing may
    // start a second change while one is running.
    final canChangeRevision = !_isDownloading && !_isChangingRevision;

    final name = revision.name.isEmpty ? null : revision.name;
    final size = state.detailsAreResolved || revision.size > 0
        ? revision.size
        : null;

    // The download names the file it saves, so it waits for a name. On the
    // fast path with `n` embedded this is true immediately; with `hid=1` it
    // becomes true a moment later, when the metadata resolves.
    final canDownload = name != null && revision.dataTxId.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.isPinned && state.showsLatestRevision) ...[
          SharedFileLatestVersionNotice(
            isDisabled: !canChangeRevision,
            onPressed: () => _changeRevision(
              () => context.read<SharedFileCubit>().showSharedRevision(),
            ),
          ),
          const SizedBox(height: 16),
        ] else if (state.newerVersionAvailable) ...[
          SharedFileFreshnessBanner(
            isPinned: state.isPinned,
            isDisabled: !canChangeRevision,
            onPressed: () => _changeRevision(
              () => context.read<SharedFileCubit>().showLatestRevision(),
            ),
          ),
          const SizedBox(height: 16),
        ],
        SharedFileIdentity(
          name: name,
          size: size,
          contentType: revision.dataContentType ?? payload?.contentType,
          thumbnailTxId: _thumbnailTxId(state, revision),
          // A private file's thumbnail is encrypted under the file key, so the
          // recipient's own access key is what renders it.
          fileKey: state.fileKey,
          ownerAddress: state.ownerAddress ?? payload?.ownerAddress,
          verification: state.verification,
          isPrivate: state.fileKey != null,
          isLoading: !state.detailsAreResolved,
        ),
        const SizedBox(height: 20),
        ArDriveButton(
          // Keyed by the bytes it fetches: the key changes only when the
          // recipient has changed the target themselves, never because a newer
          // revision turned up.
          key: ValueKey('sharedFileDownload_${revision.dataTxId}'),
          maxWidth: double.infinity,
          isDisabled: !canDownload,
          icon: ArDriveIcons.download(size: 20, color: Colors.white),
          onPressed: () => _download(context, revision),
          text: appLocalizationsOf(context).download,
        ),
        // The preview reads the file through its drive, which only the
        // resolved metadata knows about.
        if (state.detailsAreResolved) ...[
          const SizedBox(height: 8),
          ArDriveButton(
            style: ArDriveButtonStyle.tertiary,
            onPressed: () => setState(() => _isPreviewOpen = !_isPreviewOpen),
            text: _isPreviewOpen
                ? appLocalizationsOf(context).sharedFileHidePreview
                : appLocalizationsOf(context).preview,
          ),
          if (_isPreviewOpen) ...[
            const SizedBox(height: 8),
            _buildPreview(context, revision),
          ],
        ],
        if (state.fileKey != null) ...[
          const SizedBox(height: 16),
          Text(
            appLocalizationsOf(context).sharedFileUnlockedWithAccessKey,
            style: ArDriveTypography.body.captionRegular(
              color: colors.themeFgSubtle,
            ),
          ),
        ],
        const SizedBox(height: 16),
        SharedFileDetailsDrawer(
          revision: revision,
          ownerAddress: state.ownerAddress ?? payload?.ownerAddress,
          licenseName: state.latestLicense?.meta.nameWithShortName,
        ),
        SharedFileVersionsDrawer(
          revisions: state.activityRevisions,
          status: state.activityStatus,
          // The revision the link named, which stays marked as the shared one
          // even while the newest is being shown.
          sharedRevision: state.sharedRevision,
          onOpened: () => context.read<SharedFileCubit>().loadActivity(),
        ),
        const SizedBox(height: 12),
        Text(
          appLocalizationsOf(context).sharedFileStoredPermanently,
          textAlign: TextAlign.center,
          style: ArDriveTypography.body.captionRegular(
            color: colors.themeFgSubtle,
          ),
        ),
      ],
    );
  }

  /// The thumbnail to show beside the name, or `null` when the file has none.
  ///
  /// The link's `thn` is a transaction id and is preferred because it is there
  /// before anything is resolved. A v1 link carries nothing, so once the
  /// metadata has resolved the file's own ArFS thumbnail record is read
  /// instead - the same record the drive explorer uses, minus the local-DB
  /// drive lookup that a recipient can never satisfy (review F15).
  String? _thumbnailTxId(SharedFileLoadSuccess state, FileRevision revision) {
    final fromLink = state.payload?.thumbnailTxId;

    if (fromLink != null && fromLink.isNotEmpty) {
      return fromLink;
    }

    if (!state.detailsAreResolved) {
      return null;
    }

    try {
      final variants = DriveDataTableItemMapper.fromRevision(
        FileRevisionBase.fromFileRevision(revision),
        false,
      ).thumbnail?.variants;

      if (variants == null || variants.isEmpty) {
        return null;
      }

      return variants.first.txId;
    } catch (_) {
      // A malformed thumbnail record costs a thumbnail, never the page.
      return null;
    }
  }

  /// Downloads [revision], and holds the target still until it is done.
  ///
  /// The returned future completes when the download dialog closes, which is
  /// what [_isDownloading] means: for as long as it is set, the page will not
  /// offer to change the bytes underneath a download that is already running.
  Future<void> _download(BuildContext context, FileRevision revision) async {
    setState(() => _isDownloading = true);

    try {
      await promptToDownloadSharedFile(
        revision: ARFSFactory().getARFSFileFromFileRevision(revision),
        context: context,
        fileKey: widget.state.fileKey,
      );
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  /// Runs a resolver call that moves the download target.
  ///
  /// The action is disabled while it runs, so a slow lookup cannot be queued up
  /// twice. If it comes back with nothing, the resolver leaves the offer
  /// standing and this re-enables it: pressing again tries again, and nothing
  /// is left spinning.
  Future<void> _changeRevision(Future<void> Function() action) async {
    // The guard lives here rather than only on the button: `isDisabled` styles
    // an [ArDriveButton], it does not stop it from reporting a tap, so a second
    // press while the first lookup is in flight still arrives here. Moving the
    // download target twice from one intent is exactly what this must not do.
    if (_isChangingRevision) {
      return;
    }

    setState(() => _isChangingRevision = true);

    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _isChangingRevision = false);
      }
    }
  }

  /// The preview is built only once it is asked for.
  ///
  /// [FsEntryPreviewCubit] starts fetching bytes the moment it is created, so
  /// creating it eagerly would mean every recipient of every shared file pays
  /// for a preview they may never open.
  Widget _buildPreview(BuildContext context, FileRevision revision) {
    final item = DriveDataTableItemMapper.fromRevision(
      FileRevisionBase.fromFileRevision(revision),
      false,
    );

    return BlocProvider<FsEntryPreviewCubit>(
      create: (context) => FsEntryPreviewCubit(
        crypto: ArDriveCrypto(),
        isSharedFile: true,
        driveId: revision.driveId,
        fileKey: widget.state.fileKey,
        maybeSelectedItem: item,
        driveDao: context.read<DriveDao>(),
        profileCubit: context.read<ProfileCubit>(),
        arweave: context.read<ArweaveService>(),
        configService: context.read<ConfigService>(),
      ),
      child: BlocBuilder<FsEntryPreviewCubit, FsEntryPreviewState>(
        builder: (context, previewState) {
          // [FsEntryPreviewOversized] extends [FsEntryPreviewUnavailable], and
          // has its own honest message about the size cap, so only the plain
          // unavailable case is rewritten here.
          if (previewState is FsEntryPreviewUnavailable &&
              previewState is! FsEntryPreviewOversized) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                appLocalizationsOf(context).sharedFilePreviewUnsupported,
                textAlign: TextAlign.center,
                style: ArDriveTypography.body.captionRegular(
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeFgSubtle,
                ),
              ),
            );
          }

          return ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360, minHeight: 120),
            child: FsEntryPreviewWidget(
              key: ValueKey(item.id),
              state: previewState,
              isSharePage: true,
              canNavigateThroughImages: false,
              previewCubit: context.read<FsEntryPreviewCubit>(),
            ),
          );
        },
      ),
    );
  }
}

/// Offers a newer revision; never substitutes one.
///
/// The offer is the same on both kinds of link, and so is the mechanism: one
/// press replaces the download target with the file's newest revision. Only the
/// word changes - a live link *gets* the latest, a pinned link *views* it -
/// because a pinned link is a promise about which bytes sit behind it.
///
/// That promise is kept in three ways: the target never moves on its own, it
/// never moves while a download is running, and once a pinned page is showing
/// the newest revision it says so, permanently, with
/// [SharedFileLatestVersionNotice] - which puts the version that was actually
/// sent back in a single tap.
class SharedFileFreshnessBanner extends StatelessWidget {
  const SharedFileFreshnessBanner({
    super.key,
    required this.isPinned,
    required this.onPressed,
    this.isDisabled = false,
  });

  final bool isPinned;
  final VoidCallback onPressed;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    return _SharedFileNoticeCard(
      message: appLocalizationsOf(context).sharedFileNewerVersionAvailable,
      actionLabel: isPinned
          ? appLocalizationsOf(context).sharedFileViewLatest
          : appLocalizationsOf(context).sharedFileGetLatest,
      onPressed: onPressed,
      isDisabled: isDisabled,
    );
  }
}

/// Says, on a pinned link, that the page is no longer showing what was sent.
///
/// Somebody who was deliberately sent a pinned version must never be left
/// guessing which bytes the Download button is about to fetch. Once they have
/// asked for the newest revision, this stays on screen until they ask for the
/// shared one back.
class SharedFileLatestVersionNotice extends StatelessWidget {
  const SharedFileLatestVersionNotice({
    super.key,
    required this.onPressed,
    this.isDisabled = false,
  });

  final VoidCallback onPressed;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    return _SharedFileNoticeCard(
      message: appLocalizationsOf(context).sharedFileShowingLatestVersion,
      actionLabel: appLocalizationsOf(context).sharedFileViewSharedVersion,
      onPressed: onPressed,
      isDisabled: isDisabled,
    );
  }
}

/// One line about the version on screen, and one thing to do about it.
class _SharedFileNoticeCard extends StatelessWidget {
  const _SharedFileNoticeCard({
    required this.message,
    required this.actionLabel,
    required this.onPressed,
    required this.isDisabled,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onPressed;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.themeInfoSubtle,
        borderRadius: BorderRadius.circular(4),
      ),
      // The action sits below the message rather than beside it. A row of
      // [Expanded] text next to a button sized to its own label overflows as
      // soon as the label is long - and these labels are sentences, on a card
      // capped at 400px, read mostly on phones.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ArDriveIcons.info(size: 16, color: colors.themeFgDefault),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: ArDriveTypography.body.captionRegular(
                    color: colors.themeFgDefault,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ArDriveButton(
              style: ArDriveButtonStyle.tertiary,
              isDisabled: isDisabled,
              onPressed: onPressed,
              text: actionLabel,
            ),
          ),
        ],
      ),
    );
  }
}

/// Where the protocol lives: collapsed by default, one tap away, and the only
/// place on this page that says "transaction".
class SharedFileDetailsDrawer extends StatelessWidget {
  const SharedFileDetailsDrawer({
    super.key,
    required this.revision,
    this.ownerAddress,
    this.licenseName,
  });

  final FileRevision revision;
  final String? ownerAddress;
  final String? licenseName;

  @override
  Widget build(BuildContext context) {
    final ownerAddress = this.ownerAddress;
    final licenseName = this.licenseName;

    return _SharedFileDrawer(
      title: appLocalizationsOf(context).sharedFileDetailsDrawerTitle,
      children: [
        _SharedFileDetailRow(
          label: appLocalizationsOf(context).fileID,
          value: revision.fileId,
        ),
        if (revision.dataTxId.isNotEmpty)
          _SharedFileDetailRow(
            label: appLocalizationsOf(context).sharedFileDetailsTransaction,
            value: revision.dataTxId,
          ),
        if (revision.metadataTxId.isNotEmpty)
          _SharedFileDetailRow(
            label: appLocalizationsOf(context).sharedFileDetailsMetadata,
            value: revision.metadataTxId,
          ),
        if (ownerAddress != null && ownerAddress.isNotEmpty)
          _SharedFileDetailRow(
            label: appLocalizationsOf(context).sharedFileDetailsOwner,
            value: ownerAddress,
          ),
        if (licenseName != null && licenseName.isNotEmpty)
          _SharedFileDetailRow(
            label: appLocalizationsOf(context).sharedFileDetailsLicense,
            value: licenseName,
            canCopy: false,
          ),
      ],
    );
  }
}

/// The file's revisions, newest first.
///
/// Replaces the share page's old Activity tab: same information, none of the
/// tab chrome, and - because a revision history costs one metadata fetch per
/// revision - not fetched at all until the recipient opens it.
///
/// The history is [SharedFileLoadSuccess.activityRevisions], never
/// `fileRevisions`: the latter is the download target and holds exactly one
/// revision on every v2 link, so reading the history from it would show a
/// one-line history of the file's own current version.
class SharedFileVersionsDrawer extends StatelessWidget {
  const SharedFileVersionsDrawer({
    super.key,
    required this.revisions,
    required this.status,
    required this.sharedRevision,
    required this.onOpened,
  });

  /// Newest first. Empty until [onOpened] has been answered.
  final List<FileRevision> revisions;

  final SharedFileActivityStatus status;

  /// The revision the link named - the one that gets marked as shared.
  final FileRevision sharedRevision;

  /// Called every time the drawer is opened; the resolver answers the first
  /// one, ignores the rest, and tries again after a failure.
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    // A history that is still coming spins; one that failed says so; one that
    // arrived empty says the same rather than spinning for ever.
    final isLoading = status == SharedFileActivityStatus.notLoaded ||
        status == SharedFileActivityStatus.loading;
    final isUnavailable =
        status == SharedFileActivityStatus.failed || revisions.isEmpty;

    return _SharedFileDrawer(
      title: appLocalizationsOf(context).sharedFileVersionHistoryTitle,
      onExpansionChanged: (isExpanded) {
        if (isExpanded) {
          onOpened();
        }
      },
      children: [
        if (isLoading)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (isUnavailable)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              appLocalizationsOf(context).sharedFileVersionHistoryUnavailable,
              style: ArDriveTypography.body.captionRegular(
                color: colors.themeFgSubtle,
              ),
            ),
          )
        else
          for (final revision in revisions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      formatDateToUtcString(revision.dateCreated),
                      style: ArDriveTypography.body.captionRegular(
                        color: colors.themeFgDefault,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    filesize(revision.size),
                    style: ArDriveTypography.body.captionRegular(
                      color: colors.themeFgSubtle,
                    ),
                  ),
                  if (revision.dataTxId == sharedRevision.dataTxId) ...[
                    const SizedBox(width: 8),
                    Text(
                      appLocalizationsOf(context).sharedFileSharedVersion,
                      style: ArDriveTypography.body.captionBold(
                        color: colors.themeFgSubtle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
      ],
    );
  }
}

/// A collapsed disclosure, styled for this page.
class _SharedFileDrawer extends StatelessWidget {
  const _SharedFileDrawer({
    required this.title,
    required this.children,
    this.onExpansionChanged,
  });

  final String title;
  final List<Widget> children;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return Theme(
      // The material divider lines fight the card's own border.
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        onExpansionChanged: onExpansionChanged,
        title: Text(
          title,
          style: ArDriveTypography.body.captionBold(
            color: colors.themeFgSubtle,
          ),
        ),
        children: children,
      ),
    );
  }
}

class _SharedFileDetailRow extends StatelessWidget {
  const _SharedFileDetailRow({
    required this.label,
    required this.value,
    this.canCopy = true,
  });

  final String label;
  final String value;
  final bool canCopy;

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
          if (canCopy) ...[
            const SizedBox(width: 8),
            ArDriveTooltip(
              message: appLocalizationsOf(context).copyTooltip,
              child: GestureDetector(
                onTap: () => Clipboard.setData(ClipboardData(text: value)),
                child: ArDriveClickArea(
                  child: ArDriveIcons.copy(
                    size: 16,
                    color: colors.themeFgSubtle,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

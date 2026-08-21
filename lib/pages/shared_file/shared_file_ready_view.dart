import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/fs_entry_preview/fs_entry_preview_cubit.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
// Both of these live in the very large drive detail library; `show` keeps the
// rest of that surface out of this file.
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart'
    show getIconForContentType;
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart'
    show FsEntryPreviewWidget;
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/pages/shared_file/shared_file_colors.dart';
import 'package:ardrive/pages/shared_file/shared_file_identity.dart';
import 'package:ardrive/pages/shared_file/shared_file_thumbnail.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/file_revision_base.dart';
import 'package:ardrive/l11n/l11n.dart';
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
///
/// On a desktop screen the same card becomes two panes: what the file is and
/// what to do with it on the left, the file itself on the right. Nothing about
/// the state machine changes, only the axis the same content is laid out on.
class SharedFileReadyView extends StatefulWidget {
  const SharedFileReadyView({
    super.key,
    required this.state,
    this.isWide = false,
  });

  final SharedFileLoadSuccess state;

  /// Whether there is room for the preview pane. Decided by the page, from the
  /// screen size, so that the frame's width and this layout always agree.
  final bool isWide;

  @override
  State<SharedFileReadyView> createState() => _SharedFileReadyViewState();
}

/// The preview pane, which a widget test measures to prove that opening the
/// preview cannot move anything.
@visibleForTesting
const Key sharedFilePreviewPaneKey = Key('sharedFilePreviewPane');

class _SharedFileReadyViewState extends State<SharedFileReadyView> {
  /// The left hand column on a wide screen: the same 368 the phone gets, so the
  /// card reads identically at both ends.
  ///
  /// With `SharedFileFrame.maxWideContentWidth` (1040) and the wide card's 24px
  /// padding that leaves 1040 - 48 - 368 - 24 = 600 for the preview, and at the
  /// narrowest desktop screen the fork fires on (951) it still leaves ~479.
  static const double _actionsColumnWidth = 368;

  static const double _paneGutter = 24;

  /// Reserved whether or not the preview is open, which is the whole point of
  /// it: the recipient presses Preview and the file appears *in place*, with
  /// the download button exactly where it was.
  static const double _previewPaneHeight = 420;

  /// How much room the phone column gives a preview that needs a box of its
  /// own - an image, a video, a rasterised PDF. A preview whose content is a
  /// sentence gets the height of the sentence; see [_previewFillsItsBox].
  static const double _inlinePreviewHeight = 360;

  /// The info panel's height, fixed so that swapping tabs never resizes it.
  ///
  /// Wide matches the preview pane beside it, so the two regions line up.
  /// Narrow is shorter than the tallest tab on purpose: a phone column is
  /// already scrolling, and a panel tall enough for every version of every file
  /// would push the preview off the top of the screen.
  static const double _infoPanelHeightWide = _previewPaneHeight;

  static const double _infoPanelHeightNarrow = 300;

  /// The largest the file's own thumbnail is drawn in the preview pane.
  ///
  /// ArDrive generates thumbnails at a 100px minimum edge, so this is roughly
  /// twice the source and about as far as one can be enlarged before it starts
  /// to look like a mistake.
  static const double _panePictureSize = 200;

  /// Open on arrival.
  ///
  /// The page exists to show someone a file, so making them ask to see it is
  /// one click that should not exist. The pane is laid out either way on the
  /// desktop card, so this fills a box that was already there rather than
  /// moving anything; the toggle stays, so it can still be closed.
  ///
  /// A type that cannot be shown answers with its own sentence rather than
  /// nothing, which is a better answer than making the recipient press Preview
  /// to be told the same thing.
  bool _isPreviewOpen = true;

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
    final state = widget.state;

    // What the page shows and downloads: the revision the link points at,
    // unless the recipient has pressed for the newest one. It never moves on
    // its own - the banner offers, and only a press takes the offer.
    final revision = state.revision;

    return widget.isWide
        ? _buildWide(context, revision)
        : _buildNarrow(context, revision);
  }

  /// The phone column, which is where most shared links are opened: identity,
  /// Download, an optional preview underneath it, then the drawers.
  Widget _buildNarrow(BuildContext context, FileRevision revision) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._buildNotice(context, isWide: false),
        ..._buildActions(context, revision, previewIsInline: true),
      ],
    );
  }

  /// The desktop card: actions left, the file itself right.
  ///
  /// Two things decide the shape. The Download button is the primary action and
  /// has to stay obvious, so it keeps the top of the reading order rather than
  /// being pushed under a preview; and the preview pane is *always* laid out,
  /// empty or not, so that pressing Preview fills a hole that was already there
  /// instead of reflowing the card under the recipient's cursor.
  ///
  /// Actions on the left also means the visual order, the widget order and the
  /// tab order are the same one, so no focus traversal policy is needed to make
  /// the keyboard reach Download first.
  Widget _buildWide(BuildContext context, FileRevision revision) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._buildNotice(context, isWide: true),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Loose rather than fixed: at the narrowest desktop width the
            // column takes what it is given instead of overflowing the row.
            Flexible(
              flex: 2,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _actionsColumnWidth,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _buildActions(
                    context,
                    revision,
                    previewIsInline: false,
                  ),
                ),
              ),
            ),
            const SizedBox(width: _paneGutter),
            Expanded(flex: 3, child: _buildPreviewPane(context, revision)),
          ],
        ),
      ],
    );
  }

  /// The version notice, when there is one, above both panes.
  List<Widget> _buildNotice(BuildContext context, {required bool isWide}) {
    final state = widget.state;

    // Nothing may move the target while bytes are on their way, and nothing may
    // start a second change while one is running.
    final canChangeRevision = !_isDownloading && !_isChangingRevision;

    if (state.isPinned && state.showsLatestRevision) {
      return [
        SharedFileLatestVersionNotice(
          isWide: isWide,
          isDisabled: !canChangeRevision,
          onPressed: () => _changeRevision(
            () => context.read<SharedFileCubit>().showSharedRevision(),
          ),
        ),
        const SizedBox(height: 16),
      ];
    }

    if (state.newerVersionAvailable) {
      return [
        SharedFileFreshnessBanner(
          isPinned: state.isPinned,
          isWide: isWide,
          isDisabled: !canChangeRevision,
          onPressed: () => _changeRevision(
            () => context.read<SharedFileCubit>().showLatestRevision(),
          ),
        ),
        const SizedBox(height: 16),
      ];
    }

    return const [];
  }

  /// Everything the recipient can act on, in the order they want it.
  ///
  /// [previewIsInline] is the only difference between the two layouts: the
  /// phone opens the preview underneath the button, the desktop card opens it
  /// in the pane beside this column.
  List<Widget> _buildActions(
    BuildContext context,
    FileRevision revision, {
    required bool previewIsInline,
  }) {
    final state = widget.state;
    final payload = state.payload;

    final name = revision.name.isEmpty ? null : revision.name;
    final size = state.detailsAreResolved || revision.size > 0
        ? revision.size
        : null;

    // The download names the file it saves, so it waits for a name. On the
    // fast path with `n` embedded this is true immediately; with `hid=1` it
    // becomes true a moment later, when the metadata resolves.
    final canDownload = name != null && revision.dataTxId.isNotEmpty;

    return [
      SharedFileIdentity(
        name: name,
        size: size,
        contentType: revision.dataContentType ?? payload?.contentType,
        // On the desktop card the picture belongs in the pane, at a size worth
        // looking at. Showing it twice, 400px apart, would be one thumbnail
        // fetch too many and one picture too many.
        thumbnailTxId: previewIsInline ? _thumbnailTxId(state, revision) : null,
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
      // resolved metadata knows about. On the desktop card the toggle lives in
      // the pane it acts on, so this column carries it only on a phone.
      if (previewIsInline && state.detailsAreResolved) ...[
        const SizedBox(height: 8),
        _buildPreviewToggle(context),
        // Kept mounted while hidden, for the reason given on the desktop
        // pane: unloading it turns "hide" into "download again".
        Visibility(
          visible: _isPreviewOpen,
          maintainState: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              _buildPreview(context, revision, isInline: true),
            ],
          ),
        ),
      ],
      if (state.fileKey != null) ...[
        const SizedBox(height: 16),
        Text(
          appLocalizationsOf(context).sharedFileUnlockedWithAccessKey,
          style: ArDriveTypography.body.captionRegular(
            color: SharedFileColors.subtle(context),
          ),
        ),
      ],
      const SizedBox(height: 16),
      // One panel, two tabs, one height. These were two stacked accordions, so
      // opening either pushed everything below it down and reading a date
      // moved the download button.
      SharedFileInfoPanel(
        height: previewIsInline
            ? _infoPanelHeightNarrow
            : _infoPanelHeightWide,
        onVersionsOpened: () => context.read<SharedFileCubit>().loadActivity(),
        details: SharedFileDetailsContent(
          revision: revision,
          ownerAddress: state.ownerAddress ?? payload?.ownerAddress,
          licenseName: state.latestLicense?.meta.nameWithShortName,
          detailsAreResolved: state.detailsAreResolved,
        ),
        versions: SharedFileVersionsContent(
          revisions: state.activityRevisions,
          status: state.activityStatus,
          currentRevision: revision,
          sharedRevision: state.sharedRevision,
          isPinned: state.isPinned,
          // Nothing may move the target while bytes are on their way, and
          // nothing may start a second change while one is running - the same
          // guard the freshness banner's actions use.
          isDisabled: _isDownloading || _isChangingRevision,
          onOpened: () => context.read<SharedFileCubit>().loadActivity(),
          onSelected: (picked) => _changeRevision(
            () => context.read<SharedFileCubit>().showRevision(picked),
          ),
        ),
      ),
    ];
  }

  /// Where the file goes on a wide screen.
  ///
  /// Its height is a constant, not a function of [_isPreviewOpen]: a pane that
  /// only existed once the preview was open would make Preview a button that
  /// resizes the page, and the download button would move out from under the
  /// pointer that is about to press it.
  ///
  /// What it must not be is empty. A 580x430 box holding one 40px glyph reads
  /// as something that failed to load, so at rest the pane shows the file's own
  /// thumbnail when the link carried one - real content, already fetched, and
  /// the closest thing to the file itself that costs nothing - and otherwise a
  /// deliberate placeholder that says what the pane is for. The bar along the
  /// bottom is the only thing that opens and closes the preview, and it sits in
  /// the same place in both states so that pressing it never moves it out from
  /// under the pointer or drops the keyboard's focus.
  ///
  /// Nothing here is fetched before it is asked for. Opening the preview
  /// automatically would spend every desktop recipient's bandwidth on bytes
  /// they may only have wanted to download - up to `previewMaxFileSize`, which
  /// is 100 MiB - so the pane fills itself with what the page already has.
  Widget _buildPreviewPane(BuildContext context, FileRevision revision) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return Container(
      key: sharedFilePreviewPaneKey,
      height: _previewPaneHeight,
      decoration: BoxDecoration(
        color: colors.themeBgCanvas,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.themeBorderDefault),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            // Centred the way `DetailsPanel` centres the same widget.
            child: Center(
              // Both are built; only one is shown.
              //
              // Swapping them meant hiding the preview *unloaded* it: the
              // subtree went, its cubit went with it, and reopening fetched the
              // file again. On a connection the gateway is rate limiting, that
              // second fetch is one that can simply fail - so hiding a file you
              // had could lose it.
              //
              // `maintainState` keeps the preview mounted and its bytes in
              // hand while it is out of sight. Nothing is cached anywhere new;
              // the thing just never unloads.
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Visibility(
                    visible: !_isPreviewOpen,
                    maintainState: true,
                    child: _buildPaneAtRest(context, revision),
                  ),
                  Visibility(
                    visible: _isPreviewOpen,
                    maintainState: true,
                    child: _buildPreview(context, revision, isInline: false),
                  ),
                ],
              ),
            ),
          ),
          if (widget.state.detailsAreResolved) _buildPaneBar(context),
        ],
      ),
    );
  }

  /// The pane before anything has been asked of it.
  Widget _buildPaneAtRest(BuildContext context, FileRevision revision) {
    final state = widget.state;
    final contentType = revision.dataContentType ?? state.payload?.contentType;
    final thumbnailTxId = _thumbnailTxId(state, revision);

    // Decorative in both branches: the file's name and type are written out in
    // words in the column beside this one.
    final icon = ExcludeSemantics(
      child: getIconForContentType(
        contentType ?? 'application/octet-stream',
        size: 40,
        color: SharedFileColors.subtle(context),
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (thumbnailTxId != null)
            SharedFileThumbnail(
              txId: thumbnailTxId,
              size: _panePictureSize,
              // The picture is of the file, and here it is the picture the
              // recipient came to look at rather than a 44px decoration.
              fit: BoxFit.contain,
              semanticLabel: revision.name.isEmpty ? null : revision.name,
              isPrivate: state.fileKey != null,
              fileKey: state.fileKey,
              fallback: _buildIconTile(context, icon),
            )
          else
            _buildIconTile(context, icon),
          const SizedBox(height: 16),
          Text(
            state.detailsAreResolved
                ? appLocalizationsOf(context).sharedFilePreviewPaneHint
                : appLocalizationsOf(context).sharedFileLoadingDetails,
            textAlign: TextAlign.center,
            style: ArDriveTypography.body.captionRegular(
              color: SharedFileColors.subtle(context),
            ),
          ),
        ],
      ),
    );
  }

  /// The type icon, given enough weight to read as a placeholder rather than as
  /// a stray glyph in a large empty box.
  Widget _buildIconTile(BuildContext context, Widget icon) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: colors.themeBgSubtle,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(child: icon),
    );
  }

  /// The pane's own footer: one control, in one place, in both states.
  Widget _buildPaneBar(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.themeBorderDefault)),
      ),
      child: Center(child: _buildPreviewToggle(context)),
    );
  }

  Widget _buildPreviewToggle(BuildContext context) {
    return ArDriveButton(
      style: ArDriveButtonStyle.tertiary,
      onPressed: () => setState(() => _isPreviewOpen = !_isPreviewOpen),
      text: _isPreviewOpen
          ? appLocalizationsOf(context).sharedFileHidePreview
          : appLocalizationsOf(context).preview,
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

    final payload = widget.state.payload;

    // The link's own cipher, handed to the download so it does not re-fetch
    // tags the link already delivered - the reason `c` and `iv` are in the
    // schema at all.
    //
    // Only for a data item the link says is bundled. `verifyDownload` turns on
    // the arweave client's chunk check for L1 transactions and is decided by a
    // tag on that same lookup, so skipping the lookup for something that might
    // be L1 would drop a check without saying so. A bundled item is not an L1
    // transaction, so for those there is nothing to drop.
    //
    // It must also be *this* revision's cipher: the recipient may have moved
    // the page to a newer one, whose bytes the link never described.
    final linkDescribesTarget = payload != null &&
        payload.hasCipherDetails &&
        payload.bundledInTxId != null &&
        payload.dataTxId == revision.dataTxId;

    try {
      await promptToDownloadSharedFile(
        revision: ARFSFactory().getARFSFileFromFileRevision(revision),
        context: context,
        fileKey: widget.state.fileKey,
        cipher: linkDescribesTarget ? payload.cipher : null,
        cipherIv: linkDescribesTarget ? payload.cipherIv : null,
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
  /// for a preview they may never open - which is also why the wide layout
  /// reserves *space* for the preview rather than opening one.
  ///
  /// The desktop card bounds it with the pane's own height. The phone column
  /// bounds only what needs bounding: see [_previewFillsItsBox].
  Widget _buildPreview(
    BuildContext context,
    FileRevision revision, {
    required bool isInline,
  }) {
    final item = DriveDataTableItemMapper.fromRevision(
      FileRevisionBase.fromFileRevision(revision),
      false,
    );

    return AnimatedSwitcher(
      // Short, and a fade rather than a slide: the pane is not moving, its
      // contents are being replaced. Long enough not to read as a flicker,
      // short enough that picking a version still feels immediate.
      duration: const Duration(milliseconds: 180),
      child: BlocProvider<FsEntryPreviewCubit>(
        // Keyed on the bytes being previewed.
        //
        // Without this the provider builds its cubit once and keeps it, so
        // moving the target left the preview showing the revision the page
        // opened on while Download fetched a different one - two answers to
        // "what am I looking at", and the quieter one was wrong. That was
        // already reachable through "Get latest" before the version list
        // existed; the list only made it easy to hit.
        key: ValueKey(revision.dataTxId),
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
            final preview = _buildPreviewBody(context, previewState, item);

            if (!isInline) {
              return preview;
            }

            // On a phone the preview is part of a scrolling column, so a state
            // whose content is one sentence gets the height of one sentence. A
            // fixed 360 band around it left dead space above and below it and
            // pushed the drawers under it off the screen.
            return _previewFillsItsBox(previewState)
                ? SizedBox(height: _inlinePreviewHeight, child: preview)
                : preview;
          },
        ),
      ),
    );
  }

  Widget _buildPreviewBody(
    BuildContext context,
    FsEntryPreviewState previewState,
    ArDriveDataTableItem item,
  ) {
    // [FsEntryPreviewOversized] extends [FsEntryPreviewUnavailable]. Both are
    // a sentence in a box, and both are rendered here rather than by
    // [FsEntryPreviewWidget], whose versions of them fill whatever box they
    // are handed.
    if (previewState is FsEntryPreviewOversized) {
      return _buildPreviewMessage(
        context,
        appLocalizationsOf(context)
            .filePreviewTooLarge(filesize(previewState.maxFileSize)),
      );
    }

    if (previewState is FsEntryPreviewUnavailable) {
      return _buildPreviewMessage(
        context,
        appLocalizationsOf(context).sharedFilePreviewUnsupported,
      );
    }

    return FsEntryPreviewWidget(
      key: ValueKey(item.id),
      state: previewState,
      isSharePage: true,
      canNavigateThroughImages: false,
      previewCubit: context.read<FsEntryPreviewCubit>(),
    );
  }

  Widget _buildPreviewMessage(BuildContext context, String message) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: ArDriveTypography.body.captionRegular(
          color: SharedFileColors.subtle(context),
        ),
      ),
    );
  }

  /// Whether [previewState] is one that wants a box of its own.
  ///
  /// An image, a video, a document and a rasterised PDF all need somewhere to
  /// be; so does the spinner that precedes them, or the column would jump the
  /// moment the bytes arrived. A PDF with no bytes degrades to a card the size
  /// of its own content, and so do the two message states, which are handled
  /// here rather than by [FsEntryPreviewWidget].
  bool _previewFillsItsBox(FsEntryPreviewState previewState) {
    if (previewState is FsEntryPreviewUnavailable) {
      return false;
    }

    if (previewState is FsEntryPreviewPdf) {
      return previewState.pdfBytes != null;
    }

    return true;
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
    this.isWide = false,
    this.isDisabled = false,
  });

  final bool isPinned;
  final VoidCallback onPressed;

  /// Whether there is room to put the action beside the message.
  final bool isWide;

  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    return _SharedFileNoticeCard(
      message: appLocalizationsOf(context).sharedFileNewerVersionAvailable,
      actionLabel: isPinned
          ? appLocalizationsOf(context).sharedFileViewLatest
          : appLocalizationsOf(context).sharedFileGetLatest,
      onPressed: onPressed,
      isWide: isWide,
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
    this.isWide = false,
    this.isDisabled = false,
  });

  final VoidCallback onPressed;

  /// Whether there is room to put the action beside the message.
  final bool isWide;

  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    return _SharedFileNoticeCard(
      message: appLocalizationsOf(context).sharedFileShowingLatestVersion,
      actionLabel: appLocalizationsOf(context).sharedFileViewSharedVersion,
      onPressed: onPressed,
      isWide: isWide,
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
    required this.isWide,
    required this.isDisabled,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onPressed;
  final bool isWide;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    // Not `themeInfoSubtle`: that token is the same pale blue in both themes,
    // and the dark theme paints white text on it. See [SharedFileColors].
    final background = SharedFileColors.noticeBackground(context);
    final foreground = SharedFileColors.onNotice(context);

    return Container(
      padding: EdgeInsets.all(isWide ? 4 : 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: isWide
          ? _buildRow(context, foreground)
          : _buildColumn(context, foreground),
    );
  }

  /// On the wide card the notice is a bar: one line, the sentence on the left
  /// and the action on the right. Stacked across 1040px it was a short sentence
  /// pinned to one corner, a link pinned to another and a hundred pixels of
  /// empty grey in between.
  Widget _buildRow(BuildContext context, Color foreground) {
    return Row(
      children: [
        const SizedBox(width: 8),
        _buildIcon(foreground),
        const SizedBox(width: 8),
        Expanded(child: _buildMessage(foreground)),
        const SizedBox(width: 16),
        _buildAction(),
      ],
    );
  }

  /// On a phone the action sits below the message. A row of [Expanded] text
  /// next to a button sized to its own label overflows as soon as the label is
  /// long - and these labels are sentences, on a card capped at 400px.
  Widget _buildColumn(BuildContext context, Color foreground) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildIcon(foreground),
            const SizedBox(width: 8),
            Expanded(child: _buildMessage(foreground)),
          ],
        ),
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerRight, child: _buildAction()),
      ],
    );
  }

  /// The sentence next to it says everything the icon does, so the icon is not
  /// read out as well.
  Widget _buildIcon(Color foreground) => ExcludeSemantics(
        child: ArDriveIcons.info(size: 16, color: foreground),
      );

  Widget _buildMessage(Color foreground) => Text(
        message,
        style: ArDriveTypography.body.captionRegular(color: foreground),
      );

  Widget _buildAction() => ArDriveButton(
        style: ArDriveButtonStyle.tertiary,
        isDisabled: isDisabled,
        // A tertiary [ArDriveButton] is an [ArDriveTextButton], which is handed
        // nothing but a label and a callback: `isDisabled` styles the other two
        // variants and does nothing here. Withdrawing the callback is what
        // takes the button out of the focus order and tells a screen reader it
        // is unavailable, which is what should happen while a version change is
        // in flight.
        onPressed: isDisabled ? null : onPressed,
        text: actionLabel,
      );
}

/// Where the protocol lives: collapsed by default, one tap away, and the only
/// place on this page that says "transaction".
class SharedFileDetailsDrawer extends StatelessWidget {
  const SharedFileDetailsDrawer({
    super.key,
    required this.revision,
    this.ownerAddress,
    this.licenseName,
    this.detailsAreResolved = true,
  });

  final FileRevision revision;
  final String? ownerAddress;
  final String? licenseName;

  /// Whether [revision] holds the file's own record rather than what the link
  /// claimed.
  ///
  /// A v2 link carries no timestamps, so until the metadata resolves the dates
  /// on [revision] are the epoch placeholder. Showing those would put
  /// "1970-01-01" in front of a recipient as though it were the upload date,
  /// which is worse than showing nothing.
  final bool detailsAreResolved;

  @override
  Widget build(BuildContext context) => _SharedFileDrawer(
        title: appLocalizationsOf(context).sharedFileDetailsDrawerTitle,
        children: [
          SharedFileDetailsContent(
            revision: revision,
            ownerAddress: ownerAddress,
            licenseName: licenseName,
            detailsAreResolved: detailsAreResolved,
          ),
        ],
      );
}

/// What the details panel says, without the panel.
///
/// Split out from [SharedFileDetailsDrawer] so the same rows can be a tab's
/// content as easily as a disclosure's: the page is moving from stacked
/// accordions - each of which resized the card - to one panel that swaps its
/// contents in place. This holds the content half of that.
class SharedFileDetailsContent extends StatelessWidget {
  const SharedFileDetailsContent({
    super.key,
    required this.revision,
    this.ownerAddress,
    this.licenseName,
    this.detailsAreResolved = true,
  });

  final FileRevision revision;
  final String? ownerAddress;
  final String? licenseName;

  /// Whether [revision] holds the file's own record rather than what the link
  /// claimed.
  ///
  /// A v2 link carries no timestamps, so until the metadata resolves the dates
  /// on [revision] are the epoch placeholder. Showing those would put
  /// "1970-01-01" in front of a recipient as though it were the upload date,
  /// which is worse than showing nothing.
  final bool detailsAreResolved;

  @override
  Widget build(BuildContext context) {
    final ownerAddress = this.ownerAddress;
    final licenseName = this.licenseName;

    final contentType = revision.dataContentType;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Type and dates lead, ahead of the identifiers. A recipient who was
        // sent a link by a stranger has almost no way to judge what they are
        // looking at, and *when it was uploaded* is the most useful signal
        // they have - it was previously nowhere on this page, and the only
        // date anywhere sat inside the version history, which is collapsed and
        // not fetched until it is opened.
        if (contentType != null && contentType.isNotEmpty)
          _SharedFileDetailRow(
            label: appLocalizationsOf(context).fileType,
            value: contentType,
            canCopy: false,
          ),
        if (detailsAreResolved) ...[
          _SharedFileDetailRow(
            label: appLocalizationsOf(context).dateCreated,
            value: formatDateToUtcString(revision.dateCreated),
            canCopy: false,
          ),
          _SharedFileDetailRow(
            label: appLocalizationsOf(context).lastUpdated,
            value: formatDateToUtcString(revision.lastModifiedDate),
            canCopy: false,
          ),
        ],
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
        // The identifiers, one step further in.
        //
        // This file's own rule is that a recipient should be able to get their
        // file without ever learning what a transaction id is - and until the
        // details became a tab, a closed drawer was what kept that true. A tab
        // that opens by default cannot, so the ids move behind their own
        // disclosure and the tab leads with what a person can actually use.
        _SharedFileDrawer(
          title: appLocalizationsOf(context).sharedFileTransactionDetails,
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
          ],
        ),
      ],
    );
  }
}

/// The file's revisions, newest first, as something the recipient can act on.
///
/// Replaces the share page's old Activity tab: same information, none of the
/// tab chrome, and - because a revision history costs one metadata fetch per
/// revision - not fetched at all until the recipient opens it.
///
/// The history is [SharedFileLoadSuccess.activityRevisions], never
/// `fileRevisions`: the latter is the download target and holds exactly one
/// revision on every v2 link, so reading the history from it would show a
/// one-line history of the file's own current version.
///
/// ## Why this never makes the recipient wait
///
/// The version the link named is already in hand before the list is opened -
/// it is what the page is showing - so the resolver seeds the list with it and
/// this renders that row from the first frame. Everything else fills in around
/// it. Nothing here gates Download, the preview, or anything above the card,
/// and a lookup that fails costs the list and nothing else: the row the
/// recipient was sent stays, and stays selected.
class SharedFileVersionsDrawer extends StatelessWidget {
  const SharedFileVersionsDrawer({
    super.key,
    required this.revisions,
    required this.status,
    required this.sharedRevision,
    required this.currentRevision,
    required this.onOpened,
    required this.onSelected,
    this.isDisabled = false,
    this.isPinned = false,
  });

  /// Newest first. Seeded with the shared revision the moment the list opens.
  final List<FileRevision> revisions;

  final SharedFileActivityStatus status;

  /// The revision the link named - the one that wears the "this link" chip.
  final FileRevision sharedRevision;

  /// The revision the page is currently showing and would download.
  final FileRevision currentRevision;

  /// Called every time the drawer is opened; the resolver answers the first
  /// one, ignores the rest, and tries again after a failure.
  final VoidCallback onOpened;

  /// Called with the revision the recipient picked.
  final ValueChanged<FileRevision> onSelected;

  /// True while a download or another selection is in flight - nothing may
  /// move the target while bytes are on their way.
  final bool isDisabled;

  /// Whether the link deliberately names one revision.
  ///
  /// Only changes what the link's own row is *called*. A pinned link is the
  /// sharer saying which version they mean, not a restriction on the
  /// recipient - who can reach every other version of the file on chain
  /// regardless - so selecting away from it stays as free as it already is
  /// from the freshness banner, which offers a pinned link "View latest" and
  /// hands it back with [SharedFileCubit.showSharedRevision].
  final bool isPinned;

  @override
  Widget build(BuildContext context) => _SharedFileDrawer(
        title: appLocalizationsOf(context).sharedFileVersionHistoryTitle,
        onExpansionChanged: (isExpanded) {
          if (isExpanded) {
            onOpened();
          }
        },
        children: [
          SharedFileVersionsContent(
            revisions: revisions,
            status: status,
            sharedRevision: sharedRevision,
            currentRevision: currentRevision,
            onOpened: onOpened,
            onSelected: onSelected,
            isDisabled: isDisabled,
            isPinned: isPinned,
          ),
        ],
      );
}

/// The version list, without the panel around it.
///
/// Split out from [SharedFileVersionsDrawer] for the same reason the details
/// rows were: the page is moving from stacked accordions - each of which
/// resized the card - to one panel that swaps its contents in place.
class SharedFileVersionsContent extends StatelessWidget {
  const SharedFileVersionsContent({
    super.key,
    required this.revisions,
    required this.status,
    required this.sharedRevision,
    required this.currentRevision,
    required this.onOpened,
    required this.onSelected,
    this.isDisabled = false,
    this.isPinned = false,
  });

  /// Newest first. Seeded with the shared revision the moment the list opens.
  final List<FileRevision> revisions;

  final SharedFileActivityStatus status;

  /// The revision the link named - the one that wears the "shared" chip.
  final FileRevision sharedRevision;

  /// The revision the page is currently showing and would download.
  final FileRevision currentRevision;

  /// Asks the resolver for the history. Answered once, ignored while it is
  /// loading or loaded, and tried again after a failure - so it doubles as the
  /// retry.
  final VoidCallback onOpened;

  /// Called with the revision the recipient picked.
  final ValueChanged<FileRevision> onSelected;

  /// True while a download or another selection is in flight - nothing may
  /// move the target while bytes are on their way.
  final bool isDisabled;

  /// Whether the link deliberately names one revision.
  final bool isPinned;

  @override
  Widget build(BuildContext context) {
    final isLoading = status == SharedFileActivityStatus.notLoaded ||
        status == SharedFileActivityStatus.loading;
    final hasFailed = status == SharedFileActivityStatus.failed;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (revisions.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              appLocalizationsOf(context).sharedFileChooseVersion,
              style: ArDriveTypography.body.captionRegular(
                color: SharedFileColors.subtle(context),
              ),
            ),
          ),
        for (final revision in revisions)
          _SharedFileVersionRow(
            revision: revision,
            isSelected: revision.dataTxId == currentRevision.dataTxId,
            isNewest: revision.dataTxId == revisions.first.dataTxId &&
                revisions.length > 1,
            isFromLink: revision.dataTxId == sharedRevision.dataTxId,
            isPinned: isPinned,
            isDisabled: isDisabled,
            onSelected: () => onSelected(revision),
          ),
        if (isLoading)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              appLocalizationsOf(context).sharedFileVersionsLooking,
              style: ArDriveTypography.body.captionRegular(
                color: SharedFileColors.subtle(context),
              ),
            ),
          ),
        if (hasFailed)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    appLocalizationsOf(context)
                        .sharedFileVersionsUnavailableShort,
                    style: ArDriveTypography.body.captionRegular(
                      color: SharedFileColors.subtle(context),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // The drawer's own retry: `loadActivity` runs again after a
                // failure, so pressing this is all it takes.
                ArDriveTextButton(
                  text: appLocalizationsOf(context).sharedFileRetry,
                  onPressed: onOpened,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One version, and the control that selects it.
///
/// A row rather than a line of text: choosing a version is what this list is
/// for. Laid out so the same row works under a thumb - the whole row is the
/// target, and it is never shorter than 44px.
class _SharedFileVersionRow extends StatelessWidget {
  const _SharedFileVersionRow({
    required this.revision,
    required this.isSelected,
    required this.isNewest,
    required this.isFromLink,
    required this.isPinned,
    required this.isDisabled,
    required this.onSelected,
  });

  final FileRevision revision;
  final bool isSelected;
  final bool isNewest;
  final bool isFromLink;
  final bool isPinned;
  final bool isDisabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final subtle = SharedFileColors.subtle(context);

    final hasDate = !SharedFileCubit.isUnknownDate(revision.dateCreated);

    // "Pinned" says the sharer chose this version; "This link" says only that
    // the link carried it. On a pinned link the first is the fact worth
    // knowing, and it is what makes the way back obvious after selecting
    // something else.
    final label = isFromLink
        ? (isPinned
            ? appLocalizationsOf(context).sharedFileVersionPinned
            : appLocalizationsOf(context).sharedFileSharedVersion)
        : (isNewest
            ? appLocalizationsOf(context).sharedFileVersionLatest
            : null);

    return Semantics(
      selected: isSelected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: isDisabled || isSelected ? null : onSelected,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? colors.themeBgSubtle : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              _VersionRadio(isSelected: isSelected),
              const SizedBox(width: 11),
              // A row's label is what identifies that version, which is
              // normally its date. The row seeded from the link has no date to
              // give - a link carries no timestamps - so it is named by what it
              // is instead, and its chip is not repeated after the label.
              //
              // Rendering the placeholder would put "Jan 1, 1970" in front of
              // the recipient and then silently correct it when the history
              // arrived, which is exactly what it looked like.
              if (hasDate)
                Expanded(
                  child: ArDriveTooltip(
                    // The row shows the short date so that it still fits beside
                    // a size and a chip on a phone; the exact timestamp is one
                    // hover away, the same pairing the drive explorer uses.
                    message: formatDateToUtcString(revision.dateCreated),
                    child: Text(
                      yMMdDateFormatter.format(revision.dateCreated),
                      overflow: TextOverflow.ellipsis,
                      style: isSelected
                          ? ArDriveTypography.body
                              .captionBold(color: colors.themeFgDefault)
                          : ArDriveTypography.body
                              .captionRegular(color: colors.themeFgDefault),
                    ),
                  ),
                )
              else
                Expanded(
                  child: Text(
                    label ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: ArDriveTypography.body
                        .captionBold(color: colors.themeFgDefault),
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                filesize(revision.size),
                style: ArDriveTypography.body.captionRegular(color: subtle),
              ),
              // At most one chip. A row that is both the newest and the one the
              // link named would otherwise carry two labels saying much the
              // same thing, and on a phone that is what pushes it over.
              if (hasDate && label != null) ...[
                const SizedBox(width: 8),
                _VersionChip(label),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The selected mark. Drawn rather than themed so that it reads as a choice
/// even where the platform's own radio does not fit this card's density.
class _VersionRadio extends StatelessWidget {
  const _VersionRadio({required this.isSelected});

  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = ArDriveTheme.of(context).themeData;
    final colors = theme.colors;
    final colorTokens = theme.colorTokens;

    return ExcludeSemantics(
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? colors.themeFgDefault : null,
          border: Border.all(
            color:
                isSelected ? colors.themeFgDefault : colorTokens.strokeMid,
            width: isSelected ? 4.5 : 1.5,
          ),
        ),
      ),
    );
  }
}

class _VersionChip extends StatelessWidget {
  const _VersionChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: colors.themeBgSubtle,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: ArDriveTypography.body.captionBold(
          color: SharedFileColors.subtle(context),
        ),
      ),
    );
  }
}

/// Everything *about* the file, in a panel that does not change size.
///
/// The card used to carry two accordions and a preview toggle, so opening any
/// of them pushed everything below it down: reading a date moved the download
/// button. Details and Versions are tabs here instead. They swap in place, the
/// panel keeps its height, and nothing outside it moves.
///
/// The height is fixed rather than fitted for exactly that reason - a panel
/// sized to its tallest tab would still jump between them. Content longer than
/// the panel scrolls inside it.
class SharedFileInfoPanel extends StatefulWidget {
  const SharedFileInfoPanel({
    super.key,
    required this.details,
    required this.versions,
    required this.onVersionsOpened,
    required this.height,
  });

  final Widget details;
  final Widget versions;

  /// Asks the resolver for the history, the first time the Versions tab is
  /// chosen. The history costs one metadata fetch per revision, so it stays
  /// unasked-for until somebody looks.
  final VoidCallback onVersionsOpened;

  final double height;

  @override
  State<SharedFileInfoPanel> createState() => _SharedFileInfoPanelState();
}

class _SharedFileInfoPanelState extends State<SharedFileInfoPanel> {
  int _tab = 0;

  void _select(int tab) {
    if (tab == _tab) {
      return;
    }

    setState(() => _tab = tab);

    if (tab == 1) {
      widget.onVersionsOpened();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        border: Border.all(color: colors.themeBorderDefault),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                Expanded(
                  child: _SharedFileTab(
                    label: appLocalizationsOf(context)
                        .sharedFileDetailsDrawerTitle,
                    isSelected: _tab == 0,
                    onSelected: () => _select(0),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _SharedFileTab(
                    label: appLocalizationsOf(context)
                        .sharedFileVersionHistoryTitle,
                    isSelected: _tab == 1,
                    onSelected: () => _select(1),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
              child: _tab == 0 ? widget.details : widget.versions,
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the panel's two tabs.
class _SharedFileTab extends StatelessWidget {
  const _SharedFileTab({
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return Semantics(
      selected: isSelected,
      button: true,
      child: InkWell(
        onTap: isSelected ? null : onSelected,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          // The same floor the version rows use, so a tab is never a smaller
          // target than the list it opens.
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? colors.themeBgSubtle : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: isSelected
                ? ArDriveTypography.body.captionBold(
                    color: colors.themeFgDefault,
                  )
                : ArDriveTypography.body.captionRegular(
                    color: SharedFileColors.subtle(context),
                  ),
          ),
        ),
      ),
    );
  }
}

/// A collapsed disclosure, styled for this page.
///
/// [ExpansionTile] is already a keyboard control - it is a [ListTile], so it
/// takes focus and opens on Enter or Space - but in this Flutter version it
/// reports no expansion state to a screen reader at all. Tracking the state
/// here is only so that the header can say whether it is open.
class _SharedFileDrawer extends StatefulWidget {
  const _SharedFileDrawer({
    required this.title,
    required this.children,
    this.onExpansionChanged,
  });

  final String title;
  final List<Widget> children;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  State<_SharedFileDrawer> createState() => _SharedFileDrawerState();
}

class _SharedFileDrawerState extends State<_SharedFileDrawer> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
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
        onExpansionChanged: (isExpanded) {
          setState(() => _isExpanded = isExpanded);
          widget.onExpansionChanged?.call(isExpanded);
        },
        title: Semantics(
          header: true,
          expanded: _isExpanded,
          child: Text(
            widget.title,
            style: ArDriveTypography.body.captionBold(
              color: SharedFileColors.subtle(context),
            ),
          ),
        ),
        children: widget.children,
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: ArDriveTypography.body.captionRegular(
                color: SharedFileColors.subtle(context),
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
            _SharedFileCopyButton(value: value),
          ],
        ],
      ),
    );
  }
}

/// Copies one value out of the details drawer.
///
/// It was a 16px [GestureDetector]: too small to hit on a phone, invisible to
/// a screen reader, and impossible to reach with the Tab key. The icon is still
/// 16px - it is the *target* that is 44, the smallest a control on a touch
/// screen is allowed to be - and the [InkWell] underneath it is what puts the
/// control in the focus order and answers Enter and Space.
class _SharedFileCopyButton extends StatelessWidget {
  const _SharedFileCopyButton({required this.value});

  static const double _tapTarget = 44;

  final String value;

  @override
  Widget build(BuildContext context) {
    final label = appLocalizationsOf(context).copyTooltip;

    return ArDriveTooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: SizedBox(
          width: _tapTarget,
          height: _tapTarget,
          child: InkWell(
            borderRadius: BorderRadius.circular(_tapTarget / 2),
            onTap: () => Clipboard.setData(ClipboardData(text: value)),
            child: Center(
              child: ExcludeSemantics(
                child: ArDriveIcons.copy(
                  size: 16,
                  color: SharedFileColors.subtle(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

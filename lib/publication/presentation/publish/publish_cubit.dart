import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ardrive/arns/domain/arns_nameable_item.dart';
import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog_cubit.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/domain/drive_state_creation_service.dart';
import 'package:ardrive/drive_state/domain/drive_state_format_version.dart';
import 'package:ardrive/drive_state/domain/drive_state_publish_cost.dart';
import 'package:ardrive/drive_state/domain/drive_state_sync_skip_status.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/publication/data/publication_repository.dart';
import 'package:ardrive/publication/domain/publication_images.dart';
import 'package:ardrive/publication/domain/publication_publisher.dart';
import 'package:ardrive/publication/domain/publication_scope.dart';
import 'package:ardrive/publication/domain/publication_social_card.dart';
import 'package:ardrive/services/arconnect/arconnect_prompt.dart';
import 'package:ardrive/services/license/license.dart';
import 'package:ardrive/utils/leave_page_guard/leave_page_guard.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:drift/drift.dart' show Variable;
import 'package:equatable/equatable.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

part 'publish_state.dart';

/// The most keywords a publication carries.
const publicationMaxKeywords = 5;
const publicationTitleMax = 60;
const publicationDescriptionMax = 160;
const publicationOwnerNameMax = 40;

/// What a publish needs from outside the dialog, so tests can stand it in.
class PublishDependencies {
  const PublishDependencies({
    required this.driveDao,
    required this.profileCubit,
    required this.syncSkipSource,
    required this.repository,
    required this.publisher,
    required this.creationService,
    required this.discovery,
    required this.costEstimator,
    required this.viewer,
    required this.labels,
    required this.cardMark,
    required this.fileCountLabel,
    this.syncDrive,
  });

  final DriveDao driveDao;
  final ProfileCubit profileCubit;
  final DriveStateSyncSkipSource syncSkipSource;
  final PublicationRepository repository;
  final PublicationPublisher publisher;
  final DriveStateCreationService creationService;
  final DriveStateDiscovery discovery;
  final DriveStatePublishCostEstimator costEstimator;

  /// The release new publications run (`AppConfig.publicationViewer`).
  final String viewer;
  final PublicationLabels labels;

  /// ArDrive's mark for the generated card.
  final Future<ui.Image> Function() cardMark;

  /// "N files", worded.
  final String Function(int count) fileCountLabel;

  /// Syncs a drive, waiting first for a sync already running, for the Sync
  /// drive button of a dialog blocked by sync; false when no sync could start.
  /// [deep] re-reads the drive from its first block: only that reads again
  /// what an earlier sync skipped, since a plain sync starts where the last
  /// one stopped and would only clear the record of the gap. [isCancelled]
  /// says the dialog has closed, so a sync not yet started never starts.
  /// Null hides the button.
  final Future<bool> Function(
    String driveId, {
    required bool deep,
    required bool Function() isCancelled,
  })? syncDrive;
}

/// The publish dialog (docs/PUBLICATIONS.md, "The publish dialog"): what is
/// included, the look, review and publish, done.
class PublishCubit extends Cubit<PublishState> {
  PublishCubit({
    required this.drive,
    required this.folder,
    required PublishDependencies dependencies,
    this.previous,
    this.names,
    this.onSettledAfterClose,
    @visibleForTesting void Function(Object holder)? holdGuard,
    @visibleForTesting void Function(Object holder)? releaseGuard,
  })  : _deps = dependencies,
        _holdGuard = holdGuard ?? holdLeavePageGuard,
        _releaseGuard = releaseGuard ?? releaseLeavePageGuard,
        super(const PublishState(stage: PublishStage.loading));

  final void Function(Object holder) _holdGuard;
  final void Function(Object holder) _releaseGuard;

  final Drive drive;

  /// The folder being published; null for the whole drive.
  final FolderEntry? folder;

  /// The publication this updates, if any.
  final Publication? previous;

  /// The name step (docs/NAMES.md): null while names are off. Its names go
  /// into publication.json, and point at the new version once it exists.
  final ArNSFlowNameCubit? names;

  /// Told how a publish ended when the dialog was closed while it ran: the
  /// page's link, or null when it stopped. Closing hides the dialog but not
  /// the upload, and a closed cubit shows nothing, so this is how the owner
  /// hears of it.
  final void Function(String? link)? onSettledAfterClose;

  final PublishDependencies _deps;

  PublicationContents? _contents;
  PublicationRelease? _release;
  PublicationSnapshotPlan? _snapshotPlan;

  /// The job the review priced, ready to publish; null while it is being
  /// priced, so a failed pricing can never publish an older look.
  PublicationJob? _job;

  /// The last job priced or run, with what it sent, and the look it was
  /// built from. Pricing again keeps it when the look is the same, and
  /// otherwise carries its snapshot over, so nothing sent is sent again.
  PublicationJob? _lastJob;
  String? _lastJobKey;

  /// A first publish's ID, fixed for this dialog: an attempt that got as far
  /// as the manifest and is then priced again stays the same publication.
  String? _publicationId;
  ui.Image? _mark;

  String get _scopeRootFolderId => folder?.id ?? drive.rootFolderId;

  String get scopeName => folder?.name ?? drive.name;

  Future<void> load() async {
    emit(const PublishState(stage: PublishStage.loading));
    try {
      final block = await _checkBlocks();
      if (isClosed) return;
      if (block != null) {
        emit(PublishState(
          stage: PublishStage.blocked,
          blocked: block.$1,
          blockedReason: block.$2,
          pendingChanges: _pendingChanges,
          summary: _contents?.summarize(),
        ));
        return;
      }
      _release ??= await _deps.repository.readRelease(_deps.viewer);
      final summary = _contents!.summarize();

      var next = PublishState(
        stage: PublishStage.included,
        summary: summary,
        title: _clip(scopeName, publicationTitleMax),
        ownerName: await _rememberedOwnerName() ?? '',
        isUpdate: previous != null,
      );
      if (previous != null) next = await _prefillFrom(previous!, next);
      if (isClosed) return;
      emit(next);

      // An update opens on the look, filled in from the published page: Next
      // keeps it, and anything to change is changed on the way.
      if (previous != null) emit(state.copyWith(stage: PublishStage.look));
    } on PublicationReadException catch (e) {
      logger.e('[publication] preparing failed', e);
      if (isClosed) return;
      emit(PublishState(
        stage: PublishStage.blocked,
        blocked: PublishBlock.other,
        blockedReason: previous != null
            ? 'The published page could not be read back from the gateway. '
                'Try again in a minute.'
            : 'ArDrive could not read the release a page runs from the '
                'gateway. Try again in a minute.',
      ));
    }
  }

  /// Whether a dialog blocked by sync can sync the drive itself.
  bool get canSyncDrive =>
      _deps.syncDrive != null && state.blocked == PublishBlock.sync;

  /// Syncs the drive and checks it again, for a dialog blocked by sync.
  Future<void> syncDrive() async {
    final sync = _deps.syncDrive;
    if (sync == null || !canSyncDrive) return;
    final deep = _deps.syncSkipSource.statusFor(drive.id).state ==
        DriveStateSyncSkipState.skipped;
    emit(const PublishState(stage: PublishStage.syncing));
    var started = true;
    try {
      started = await sync(drive.id, deep: deep, isCancelled: () => isClosed);
    } catch (e, stackTrace) {
      // The check that follows says what the sync left.
      logger.e('[publication] syncing the drive failed', e, stackTrace);
    }
    if (isClosed) return;
    await load();
    // A sync that never started leaves the same sentence, which would read
    // as the button doing nothing.
    if (!started && !isClosed && state.blocked == PublishBlock.sync) {
      emit(state.copyWith(
        blockedReason: "A sync couldn't start. Wait for any upload in "
            'progress to finish, then try again.',
      ));
    }
  }

  /// What stops publishing right now, with the sentence that says so.
  Future<(PublishBlock, String)?> _checkBlocks() async {
    final sync = _deps.syncSkipSource.statusFor(drive.id);
    if (!sync.isClean) return (PublishBlock.sync, sync.reason);

    if (folder != null && await _isHiddenOrUnderHidden(folder!)) {
      return (PublishBlock.hiddenFolder, '');
    }

    _contents = await PublicationContents.loadScope(
      _deps.driveDao,
      driveId: drive.id,
      rootFolderId: drive.rootFolderId,
      scopeRootFolderId: _scopeRootFolderId,
    );
    final summary = _contents!.summarize();
    _pendingChanges = await _countPendingChanges();
    if (_pendingChanges > 0) return (PublishBlock.pendingUploads, '');
    if (summary.isEmpty) return (PublishBlock.empty, '');
    return null;
  }

  /// Whether [start] is hidden, or inside a hidden folder: with "Show
  /// hidden" on, a folder inside a hidden one looks like any other.
  Future<bool> _isHiddenOrUnderHidden(FolderEntry start) async {
    FolderEntry? current = start;
    for (var depth = 0; current != null && depth < 256; depth++) {
      if (current.isHidden) return true;
      final parent = current.parentFolderId;
      if (parent == null) return false;
      current =
          await _deps.driveDao.folderById(folderId: parent).getSingleOrNull();
    }
    return false;
  }

  /// What the last check found waiting on Arweave, for the blocked dialog.
  int _pendingChanges = 0;

  /// How many items wait on Arweave before this can be published: the drive,
  /// its folders and its files, each counted once however many of its
  /// transactions wait.
  ///
  /// An item waits while a change to it anywhere in the drive (an upload, a
  /// rename, a hide) has metadata the app still holds as pending, which a new
  /// snapshot refuses (`unconfirmedMetadataCountSql`), or, for a file this
  /// would show, while its latest upload is pending. Pending lasts until
  /// `kRequiredTxConfirmationCount` (15) confirmations, so the wait is closer to an
  /// hour than to minutes.
  Future<int> _countPendingChanges() async {
    final db = _deps.driveDao.attachedDatabase;
    String pendingIn(String table, String idColumn) =>
        'SELECT r.$idColumn AS id FROM $table r '
        'JOIN network_transactions n ON n.id = r.metadataTxId '
        "WHERE r.driveId = ?1 AND n.status = 'pending'";
    final rows = await db.customSelect(
      '${pendingIn('drive_revisions', 'driveId')} '
      'UNION ${pendingIn('folder_revisions', 'folderId')} '
      'UNION ${pendingIn('file_revisions', 'fileId')}',
      variables: [Variable.withString(drive.id)],
    ).get();
    return {
      for (final row in rows) row.read<String>('id'),
      ..._contents!.pendingFileIds,
    }.length;
  }

  Future<PublishState> _prefillFrom(Publication p, PublishState s) async {
    final content = await _deps.repository.readContent(p.latest.txId);
    final config = content.config;

    /// The earlier version's files for [paths], kept by transaction ID; its
    /// preview is best effort, and an image whose preview cannot be read is
    /// still published as it was.
    Future<PickedImage?> existing(List<String> paths, String preview) async {
      final ids = {
        for (final path in paths)
          if (content.paths[path] case final id?) path: id,
      };
      if (ids.length != paths.length) return null;
      ui.Image? image;
      try {
        image = (await PublicationPicture.decode(
                await _deps.repository.readData(ids[preview]!)))
            .image;
      } catch (e) {
        logger.w('[publication] an earlier image could not be previewed: $e');
      }
      return PickedImage(preview: image, image: ExistingPublicationImage(ids));
    }

    final icon = config.images.icon != null
        ? await existing(
            ['icon-32.png', 'icon-180.png', 'icon-512.png'], 'icon-512.png')
        : null;
    final cover = config.images.cover != null
        ? await existing(['cover.jpg'], 'cover.jpg')
        : null;
    final socialId = content.paths['social.jpg'];
    PickedImage? ownCard;
    if (socialId != null && !content.generatedCard) {
      ownCard = await existing(['social.jpg'], 'social.jpg');
    }
    final iconPreview = icon?.preview;
    final tint = iconPreview == null ? null : await averageColor(iconPreview);
    final license = config.license;
    final prefilled = s.copyWith(
      title: config.title,
      description: config.description,
      ownerName: config.ownerName ?? s.ownerName,
      keywords: content.keywords,
      licence: () => license == null
          ? null
          : _licenceFor(license.definitionTxId, license.params),
      icon: () => icon,
      cover: () => cover,
      social: () => ownCard,
      iconTint: () => tint,
    );
    if (socialId != null && content.generatedCard) {
      // Kept as it is unless something the card shows changes.
      _previousCard = ExistingPublicationImage({'social.jpg': socialId});
      _previousCardKey = _cardKey(prefilled);
    }
    return prefilled;
  }

  ExistingPublicationImage? _previousCard;
  String? _previousCardKey;

  /// What the generated card shows, as one comparable value.
  String _cardKey(PublishState s) => [
        s.title.trim(),
        s.description.trim(),
        _imageKey(s.icon),
        _imageKey(s.cover),
        _contents?.summarize().fileCount,
      ].join('\u0000');

  /// Everything the look puts into a job's files: two jobs with the same key
  /// would sign the same page.
  String _jobKey(PublishState s) => [
        s.title.trim(),
        s.description.trim(),
        s.ownerName.trim(),
        s.keywords.join('\u0001'),
        s.licence?.toJson().toString(),
        _imageKey(s.icon),
        _imageKey(s.cover),
        s.social == null ? 'generated:${_cardKey(s)}' : _imageKey(s.social),
      ].join('\u0000');

  static String _imageKey(PickedImage? picked) => switch (picked?.image) {
        ExistingPublicationImage(:final files) => files.toString(),
        final NewPublicationImage image => 'new:${identityHashCode(image)}',
        _ => '',
      };

  PublicationLicence? _licenceFor(
    String definitionTxId,
    Map<String, String> params,
  ) {
    for (final meta in licenseMetaMap.values) {
      if (meta.licenseDefinitionTxId == definitionTxId) {
        return PublicationLicence(meta, params);
      }
    }
    return null;
  }

  // The look.

  void next() {
    switch (state.stage) {
      case PublishStage.included:
        emit(state.copyWith(stage: PublishStage.look));
      case PublishStage.look:
        if (state.titleIsValid) review();
      default:
    }
  }

  void back() {
    switch (state.stage) {
      case PublishStage.look:
        emit(state.copyWith(stage: PublishStage.included));
      case PublishStage.review:
        emit(state.copyWith(stage: PublishStage.look));
      case PublishStage.failed:
        // Back to the review with what was done kept, to add credits or
        // switch to AR; without a priced job, back to the look.
        emit(state.copyWith(
          stage: _job != null && state.cost != null
              ? PublishStage.review
              : PublishStage.look,
        ));
      default:
    }
  }

  void setTitle(String value) =>
      emit(state.copyWith(title: _clip(value, publicationTitleMax)));

  void setDescription(String value) => emit(
      state.copyWith(description: _clip(value, publicationDescriptionMax)));

  void setOwnerName(String value) =>
      emit(state.copyWith(ownerName: _clip(value, publicationOwnerNameMax)));

  void addKeyword(String value) {
    final keyword = value.trim();
    if (keyword.isEmpty ||
        state.keywords.length >= publicationMaxKeywords ||
        state.keywords.contains(keyword)) {
      return;
    }
    emit(state.copyWith(keywords: [...state.keywords, _clip(keyword, 32)]));
  }

  void removeKeyword(String keyword) => emit(
      state.copyWith(keywords: [...state.keywords.where((k) => k != keyword)]));

  void setLicence(PublicationLicence? licence) =>
      emit(state.copyWith(licence: () => licence));

  /// Uses [bytes] for [slot]: decoded by the browser and cropped to the
  /// slot's size. A picture that is not one, or too big, is refused with
  /// [PublishState.imageError].
  Future<void> pickImage(PublicationImageSlot slot, Uint8List bytes) async {
    emit(state.copyWith(imageError: () => null));
    final PublicationPicture picture;
    try {
      picture = await PublicationPicture.decode(bytes);
    } on PublicationImageException catch (e) {
      if (!isClosed) {
        emit(state.copyWith(imageError: () => (slot: slot, problem: e.reason)));
      }
      return;
    }
    final kind = switch (slot) {
      PublicationImageSlot.icon => PublicationImageKind.icon,
      PublicationImageSlot.cover => PublicationImageKind.cover,
      PublicationImageSlot.social => PublicationImageKind.social,
    };
    final files = slot == PublicationImageSlot.icon
        ? await publicationIconFiles(picture.image)
        : {
            slot == PublicationImageSlot.cover ? 'cover.jpg' : 'social.jpg':
                await publicationBannerFile(picture.image, kind),
          };
    final preview =
        await publicationCrop(picture.image, kind.width, kind.height);
    if (isClosed) return;
    final picked = PickedImage(
      preview: preview,
      image: NewPublicationImage(files),
      isSmall: picture.isSmallFor(kind),
    );
    switch (slot) {
      case PublicationImageSlot.icon:
        emit(state.copyWith(
          icon: () => picked,
          iconTint: () => null,
        ));
        final tint = await averageColor(preview);
        if (!isClosed && state.icon == picked) {
          emit(state.copyWith(iconTint: () => tint));
        }
      case PublicationImageSlot.cover:
        emit(state.copyWith(cover: () => picked));
      case PublicationImageSlot.social:
        emit(state.copyWith(social: () => picked));
    }
  }

  void removeImage(PublicationImageSlot slot) => emit(switch (slot) {
        PublicationImageSlot.icon =>
          state.copyWith(icon: () => null, iconTint: () => null),
        PublicationImageSlot.cover => state.copyWith(cover: () => null),
        PublicationImageSlot.social => state.copyWith(social: () => null),
      });

  /// ArDrive's mark, for the card preview.
  Future<ui.Image> mark() async => _mark ??= await _deps.cardMark();

  // Review.

  Future<void> review() async {
    if (!state.titleIsValid) {
      emit(state.copyWith(stage: PublishStage.look));
      return;
    }
    // Whatever was priced before may not match what the owner sees.
    _job = null;
    emit(state.copyWith(stage: PublishStage.pricing));
    final profile = _deps.profileCubit.state;
    if (profile is! ProfileLoggedIn) return;
    try {
      _snapshotPlan ??= await _planSnapshot(profile);
      final plan = _snapshotPlan;
      if (plan == null) return;
      final key = _jobKey(state);
      final job = _lastJob != null && key == _lastJobKey
          ? _lastJob!
          : (await _buildJob(profile)).carrySnapshotFrom(_lastJob);
      final cost = await _deps.costEstimator
          .estimate(
            sizeInBytes: _deps.publisher.sizeOf(job),
            itemSizes: _deps.publisher.itemSizesOf(job),
            wallet: profile.user.wallet,
            walletBalance: profile.user.walletBalance,
          )
          .timeout(const Duration(seconds: 45));
      if (isClosed) return;
      _job = _lastJob = job;
      _lastJobKey = key;
      emit(state.copyWith(
        stage: PublishStage.review,
        reusesSnapshot: plan is ReusedSnapshot,
        cost: cost,
        method: cost.defaultMethod,
      ));
    } catch (e, stackTrace) {
      logger.e('[publication] pricing failed', e, stackTrace);
      if (isClosed) return;
      emit(state.copyWith(
        stage: PublishStage.failed,
        failure: 'The cost of publishing could not be worked out. Nothing '
            'was uploaded. Try again in a moment.',
        paidTxId: () => null,
      ));
    }
  }

  /// The newest snapshot of the drive when nothing changed since it was
  /// made, else a new one. Null after emitting why a new one was refused.
  Future<PublicationSnapshotPlan?> _planSnapshot(
      ProfileLoggedIn profile) async {
    final discovered = await _deps.discovery.findCandidates(
      driveId: drive.id,
      ownerAddress: profile.user.walletAddress,
    );
    final newest = discovered.candidates
        .where((c) =>
            c.cipher == null &&
            c.unixTime != null &&
            // In a block: one still pending may be an upload whose data
            // never arrived.
            c.minedAtHeight != null &&
            DriveStateFormatVersion.tryParse(c.stateVersion) ==
                DriveStateFormatVersion.current)
        .fold<DriveStateArtifactCandidate?>(
            null,
            (best, c) =>
                best == null || c.unixTime! > best.unixTime! ? c : best);
    if (newest != null &&
        newest.entityCount == await _localEntityCount() &&
        await _unchangedSince(newest.unixTime!)) {
      // Mined is not the same as served: a page whose snapshot the gateway
      // cannot hand over never opens. One that does not serve is replaced.
      if (await _deps.publisher.snapshotServes(newest.txId)) {
        return ReusedSnapshot(txId: newest.txId, tags: newest.tags);
      }
      logger.w('[publication] snapshot ${newest.txId} does not serve; '
          'making a new one');
    }

    final prepared = await _deps.creationService.prepare(
      driveId: drive.id,
      driveKey: null,
      wallet: profile.user.wallet,
      isCancelled: () => isClosed,
    );
    if (prepared.isRefused) {
      emit(state.copyWith(
        stage: PublishStage.blocked,
        blocked: PublishBlock.other,
        blockedReason: prepared.reason,
      ));
      return null;
    }
    return NewSnapshot(prepared.artifact!);
  }

  /// What a new snapshot of the drive would count: the drive, and every
  /// folder and file with a revision (the export's own rule), so a snapshot
  /// made before something reached this device does not match.
  Future<int> _localEntityCount() async {
    final db = _deps.driveDao.attachedDatabase;
    final row = await db.customSelect(
      'SELECT (SELECT count(*) FROM folder_entries t WHERE t.driveId = ?1 '
      'AND EXISTS (SELECT 1 FROM folder_revisions r '
      'WHERE r.folderId = t.id AND r.driveId = t.driveId)) + '
      '(SELECT count(*) FROM file_entries t WHERE t.driveId = ?1 '
      'AND EXISTS (SELECT 1 FROM file_revisions r '
      'WHERE r.fileId = t.id AND r.driveId = t.driveId)) + 1 AS c',
      variables: [Variable.withString(drive.id)],
    ).getSingle();
    return row.read<int>('c');
  }

  /// Whether nothing in the drive changed after [unixTime]: no revision of
  /// the drive, a folder or a file is newer.
  Future<bool> _unchangedSince(int unixTime) async {
    final db = _deps.driveDao.attachedDatabase;
    final row = await db.customSelect(
      'SELECT max(d) AS latest FROM ('
      'SELECT max(dateCreated) AS d FROM drive_revisions WHERE driveId = ?1 '
      'UNION ALL SELECT max(dateCreated) FROM folder_revisions WHERE driveId = ?1 '
      'UNION ALL SELECT max(dateCreated) FROM file_revisions WHERE driveId = ?1)',
      variables: [Variable.withString(drive.id)],
    ).getSingle();
    final latest = row.readNullable<int>('latest');
    return latest != null && latest <= unixTime;
  }

  Future<PublicationJob> _buildJob(ProfileLoggedIn profile) async {
    final summary = _contents!.summarize();
    final keepCard = state.social == null &&
        _previousCard != null &&
        _cardKey(state) == _previousCardKey;
    final social = state.social?.image ??
        (keepCard
            ? _previousCard!
            : NewPublicationImage({
                'social.jpg': await PublicationSocialCard(
                  title: state.title.trim(),
                  description: state.description.trim(),
                  fileCount: _deps.fileCountLabel(summary.fileCount),
                  cover: state.cover?.preview,
                  icon: state.icon?.preview,
                  iconTint: state.iconTint,
                  mark: await mark(),
                ).render(),
              }));
    return PublicationJob(
      publicationId: previous?.id ?? (_publicationId ??= const Uuid().v4()),
      driveId: drive.id,
      rootFolderId: drive.rootFolderId,
      folderId: folder?.id,
      owner: profile.user.walletAddress,
      ownerName: _nonEmpty(state.ownerName.trim()),
      title: state.title.trim(),
      description: state.description.trim(),
      keywords: state.keywords,
      license: state.licence?.toJson(),
      icon: state.icon?.image,
      cover: state.cover?.image,
      social: social,
      snapshot: _snapshotPlan!,
      release: _release!,
      files: [
        for (final file in _contents!.listedFiles())
          (path: file.path, id: file.dataTxId),
      ],
      fileCount: summary.fileCount,
      generatedCard: state.social == null,
      labels: _deps.labels,
      method: state.method,
    );
  }

  void setUploadMethod(UploadMethod method) {
    if (state.stage != PublishStage.review) return;
    emit(state.copyWith(method: method));
  }

  /// Re-reads the balances after a Turbo top-up.
  Future<void> refreshBalance() async {
    final job = _job;
    final profile = _deps.profileCubit.state;
    if (job == null || profile is! ProfileLoggedIn) return;
    await Future<void>.delayed(const Duration(seconds: 2));
    try {
      final cost = await _deps.costEstimator.estimate(
        sizeInBytes: _deps.publisher.sizeOf(job),
        itemSizes: _deps.publisher.itemSizesOf(job),
        wallet: profile.user.wallet,
        walletBalance: profile.user.walletBalance,
      );
      if (!isClosed) emit(state.copyWith(cost: cost));
    } catch (e) {
      logger.w('[publication] could not refresh the balance: $e');
    }
  }

  // Publish.

  Future<void> publish() async {
    final job = _job;
    final profile = _deps.profileCubit.state;
    if (job == null || profile is! ProfileLoggedIn || !state.canPublish) return;
    try {
      if (await _deps.profileCubit.logoutIfWalletMismatch()) return;
    } on ArConnectUnavailableException catch (e) {
      // Wander couldn't be reached and the person chose Cancel. Nothing was
      // published: the review stays, to try again or close.
      logger.w('[publication] could not check the wallet: $e');
      return;
    }
    // The job keeps the method it was priced with unless the owner switched.
    final run = job.method == state.method
        ? job
        : (_job = job.withMethod(state.method));
    _lastJob = run;
    run.names = names?.plannedNames ?? const [];
    _publishing = true;
    emit(state.copyWith(
      stage: PublishStage.publishing,
      failure: '',
      naming: names?.hasWork == true ? run.names : const [],
      namingStarted: false,
    ));
    try {
      final version = await _deps.publisher.publish(
        run,
        profile.user.wallet,
        onStep: (step) {
          if (!isClosed) emit(state.copyWith(step: step));
        },
      );
      await _rememberOwnerName(state.ownerName.trim());
      // The page stands whatever happens to its names.
      final named = names;
      ArNSFlowOutcome? outcome;
      if (named != null && named.hasWork) {
        if (!isClosed) emit(state.copyWith(namingStarted: true));
        outcome = await named.applyTo(
          version.txId,
          // GraphQL lags a new version: its names read as a publication now.
          publication: ArNSPublicationItem(
            publicationId: version.publicationId,
            driveId: version.driveId,
            folderId: version.folderId,
            isLatestVersion: true,
          ),
        );
      }
      final live = outcome?.live ?? const <String>[];
      // The page and its link use the name when there is one.
      final link = live.isNotEmpty
          ? arnsUrlFor(live.last)
          : '${_deps.publisher.gatewayUrl}/${version.txId}/';
      if (isClosed) {
        onSettledAfterClose?.call(link);
        return;
      }
      emit(
          state.copyWith(stage: PublishStage.done, link: link, names: outcome));
    } on PublicationFailure catch (e) {
      if (isClosed) {
        onSettledAfterClose?.call(null);
        return;
      }
      emit(state.copyWith(
        stage: PublishStage.failed,
        failure: e.message,
        paidTxId: () => e.paidTxId,
        canRetry: e.canRetry,
      ));
    } catch (e, stackTrace) {
      // Never leave the owner on a progress screen with no way out.
      logger.e('[publication] publishing failed', e, stackTrace);
      if (isClosed) {
        onSettledAfterClose?.call(null);
        return;
      }
      emit(state.copyWith(
        stage: PublishStage.failed,
        failure: 'Publishing stopped unexpectedly. Try again to finish it. '
            'Nothing already sent is sent or charged again.',
        paidTxId: () => null,
        canRetry: true,
      ));
    } finally {
      _publishing = false;
      // A dialog closed mid-publish left the guard and the name step held
      // for this upload.
      if (isClosed) {
        _releaseGuard(this);
        await names?.close();
      }
    }
  }

  /// Whether [publish] is still running, which can outlast the dialog: a
  /// route pop closes the cubit but not the upload.
  bool _publishing = false;

  /// Keeps the browser asking before the tab is closed while a publish runs:
  /// closing it midway leaves what was paid for half sent, and only this tab
  /// holds the signed files that finish it.
  @override
  void onChange(Change<PublishState> change) {
    super.onChange(change);
    if (change.nextState.stage == PublishStage.publishing) {
      _holdGuard(this);
    } else {
      _releaseGuard(this);
    }
  }

  @override
  Future<void> close() async {
    // While an upload runs, the guard and the name step are its to release
    // (see [publish]): the names are applied after the page is up.
    if (!_publishing) {
      _releaseGuard(this);
      await names?.close();
    }
    return super.close();
  }

  /// Tries a failed publish again, reusing what it already sent.
  Future<void> retry() async {
    if (_job == null) {
      await review();
      return;
    }
    emit(state.copyWith(stage: PublishStage.review));
    await publish();
  }

  // The owner's display name, remembered from their last publication.

  String get _ownerNameKey {
    final profile = _deps.profileCubit.state;
    return profile is ProfileLoggedIn
        ? 'publicationOwnerName_${profile.user.walletAddress}'
        : 'publicationOwnerName';
  }

  Future<String?> _rememberedOwnerName() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_ownerNameKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> _rememberOwnerName(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (name.isEmpty) {
        await prefs.remove(_ownerNameKey);
      } else {
        await prefs.setString(_ownerNameKey, name);
      }
    } catch (_) {}
  }
}

String _clip(String text, int max) =>
    text.characters.length <= max ? text : text.characters.take(max).toString();

String? _nonEmpty(String text) => text.isEmpty ? null : text;

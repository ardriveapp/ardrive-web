import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

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
import 'package:ardrive/services/license/license.dart';
import 'package:ardrive/utils/logger.dart';
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
}

/// The publish dialog (docs/PUBLICATIONS.md, "The publish dialog"): what is
/// included, the look, review and publish, done.
class PublishCubit extends Cubit<PublishState> {
  PublishCubit({
    required this.drive,
    required this.folder,
    required PublishDependencies dependencies,
    this.previous,
    this.startAtLook = false,
  })  : _deps = dependencies,
        super(const PublishState(stage: PublishStage.loading));

  final Drive drive;

  /// The folder being published; null for the whole drive.
  final FolderEntry? folder;

  /// The publication this updates, if any.
  final Publication? previous;

  /// "Edit look": an update that opens on the look rather than the review.
  final bool startAtLook;

  final PublishDependencies _deps;

  PublicationContents? _contents;
  PublicationRelease? _release;
  PublicationSnapshotPlan? _snapshotPlan;
  PublicationJob? _job;
  ui.Image? _mark;

  String get _scopeRootFolderId => folder?.id ?? drive.rootFolderId;

  String get scopeName => folder?.name ?? drive.name;

  Future<void> load() async {
    emit(const PublishState(stage: PublishStage.loading));
    try {
      final block = await _checkBlocks();
      if (block != null) {
        emit(PublishState(
          stage: PublishStage.blocked,
          blocked: block.$1,
          blockedReason: block.$2,
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
      emit(next);

      if (previous != null) {
        if (startAtLook) {
          emit(state.copyWith(stage: PublishStage.look));
        } else {
          await review();
        }
      }
    } on PublicationReadException catch (e) {
      logger.e('[publication] preparing failed', e);
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

  /// What stops publishing right now, with the sentence that says so.
  Future<(PublishBlock, String)?> _checkBlocks() async {
    final sync = _deps.syncSkipSource.statusFor(drive.id);
    if (!sync.isClean) return (PublishBlock.sync, sync.reason);

    if (folder != null && folder!.isHidden) {
      return (PublishBlock.hiddenFolder, '');
    }

    _contents = await PublicationContents.loadScope(
      _deps.driveDao,
      driveId: drive.id,
      rootFolderId: drive.rootFolderId,
      scopeRootFolderId: _scopeRootFolderId,
    );
    final summary = _contents!.summarize();
    if (summary.pendingFiles > 0 || await _pendingMetadata() > 0) {
      return (PublishBlock.pendingUploads, '');
    }
    if (summary.isEmpty) return (PublishBlock.empty, '');
    return null;
  }

  Future<int> _pendingMetadata() async {
    final db = _deps.driveDao.attachedDatabase;
    final row = await db.customSelect(
      'SELECT count(*) AS c FROM network_transactions n '
      "WHERE n.status = 'pending' AND n.id IN ("
      'SELECT metadataTxId FROM drive_revisions WHERE driveId = ?1 '
      'UNION SELECT metadataTxId FROM folder_revisions WHERE driveId = ?1 '
      'UNION SELECT metadataTxId FROM file_revisions WHERE driveId = ?1)',
      variables: [Variable.withString(drive.id)],
    ).getSingle();
    return row.read<int>('c');
  }

  Future<PublishState> _prefillFrom(Publication p, PublishState s) async {
    final content = await _deps.repository.readContent(p.latest.txId);
    final config = content.config;
    Future<PickedImage?> existing(List<String> paths, String preview) async {
      final ids = {
        for (final path in paths)
          if (content.paths[path] case final id?) path: id,
      };
      if (ids.length != paths.length) return null;
      try {
        final picture = await PublicationPicture.decode(
            await _deps.repository.readData(ids[preview]!));
        return PickedImage(
          preview: picture.image,
          image: ExistingPublicationImage(ids),
        );
      } catch (e) {
        logger.w('[publication] an earlier image could not be read: $e');
        return null;
      }
    }

    final icon = config.images.icon != null
        ? await existing(
            ['icon-32.png', 'icon-180.png', 'icon-512.png'], 'icon-512.png')
        : null;
    final cover = config.images.cover != null
        ? await existing(['cover.jpg'], 'cover.jpg')
        : null;
    final license = config.license;
    return s.copyWith(
      title: config.title,
      description: config.description,
      ownerName: config.ownerName ?? s.ownerName,
      keywords: _keywordsOf(content),
      licence: () =>
          license == null ? null : _licenceFor(license.definitionTxId),
      icon: () => icon,
      cover: () => cover,
      iconTint: () => null,
    );
  }

  List<String> _keywordsOf(PublishedContent content) => content.keywords;

  PublicationLicence? _licenceFor(String definitionTxId) {
    for (final meta in licenseMetaMap.values) {
      if (meta.licenseDefinitionTxId == definitionTxId) {
        return PublicationLicence(meta);
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
      emit(state.copyWith(imageError: () => (slot: slot, problem: e.reason)));
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
    emit(state.copyWith(stage: PublishStage.pricing));
    final profile = _deps.profileCubit.state;
    if (profile is! ProfileLoggedIn) return;
    try {
      _snapshotPlan ??= await _planSnapshot(profile);
      final plan = _snapshotPlan;
      if (plan == null) return;
      final job = await _buildJob(profile);
      final cost = await _deps.costEstimator
          .estimate(
            sizeInBytes: _deps.publisher.sizeOf(job),
            wallet: profile.user.wallet,
            walletBalance: profile.user.walletBalance,
          )
          .timeout(const Duration(seconds: 45));
      if (isClosed) return;
      _job = job;
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
            DriveStateFormatVersion.tryParse(c.stateVersion) ==
                DriveStateFormatVersion.current)
        .fold<DriveStateArtifactCandidate?>(
            null,
            (best, c) =>
                best == null || c.unixTime! > best.unixTime! ? c : best);
    if (newest != null && await _unchangedSince(newest.unixTime!)) {
      return ReusedSnapshot(txId: newest.txId, tags: newest.tags);
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
    final social = state.social?.image ??
        NewPublicationImage({
          'social.jpg': await PublicationSocialCard(
            title: state.title.trim(),
            description: state.description.trim(),
            fileCount: _deps.fileCountLabel(summary.fileCount),
            cover: state.cover?.preview,
            icon: state.icon?.preview,
            iconTint: state.iconTint,
            mark: await mark(),
          ).render(),
        });
    return PublicationJob(
      publicationId: previous?.id ?? const Uuid().v4(),
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
    if (await _deps.profileCubit.logoutIfWalletMismatch()) return;
    // The job keeps the method it was priced with unless the owner switched.
    final run = job.method == state.method ? job : (_job = _withMethod(job));
    emit(state.copyWith(stage: PublishStage.publishing, failure: ''));
    try {
      final version = await _deps.publisher.publish(
        run,
        profile.user.wallet,
        onStep: (step) {
          if (!isClosed) emit(state.copyWith(step: step));
        },
      );
      await _rememberOwnerName(state.ownerName.trim());
      if (isClosed) return;
      emit(state.copyWith(
        stage: PublishStage.done,
        link: '${_deps.publisher.gatewayUrl}/${version.txId}/',
      ));
    } on PublicationFailure catch (e) {
      if (isClosed) return;
      emit(state.copyWith(
        stage: PublishStage.failed,
        failure: e.message,
        paidTxId: () => e.paidTxId,
      ));
    }
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

  PublicationJob _withMethod(PublicationJob job) => PublicationJob(
        publicationId: job.publicationId,
        driveId: job.driveId,
        rootFolderId: job.rootFolderId,
        folderId: job.folderId,
        owner: job.owner,
        ownerName: job.ownerName,
        title: job.title,
        description: job.description,
        keywords: job.keywords,
        license: job.license,
        icon: job.icon,
        cover: job.cover,
        social: job.social,
        snapshot: job.snapshot,
        release: job.release,
        files: job.files,
        fileCount: job.fileCount,
        labels: job.labels,
        method: state.method,
      );

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

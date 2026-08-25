import 'dart:async';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/license_assertion.dart';
import 'package:ardrive/entities/license_composed.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/shared_file_link.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/utils.dart';
import 'package:collection/collection.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'shared_file_state.dart';

/// [SharedFileCubit] includes logic for displaying a file shared with another user.
///
/// Two resolution paths meet here, and the difference between them is the whole
/// point of the v2 link schema (`docs/FILE_SHARING_REDESIGN_PLAN.md` §1.2, §5):
///
/// * A **v1 link** ([linkPayload] is `null`) knows nothing about the file. It
///   resolves everything over GraphQL - owner probe, revision enumeration, one
///   metadata fetch per revision - before anything can be painted. That path is
///   preserved here exactly as it was.
/// * A **v2 link** carries what the page needs: the data transaction, the name,
///   the size, the type, the cipher. Each of those skips the lookup it would
///   otherwise have cost, so a complete payload paints with **zero blocking
///   GraphQL**. Every field is independently optional, and a field the link
///   did not carry - or that arrived malformed and was dropped by the parser -
///   falls back to exactly the lookup the v1 path would have done.
///
/// The payload is an optimization, never a source of truth. Everything it
/// asserts is checked against the file's own record in the background
/// ([LinkVerification]), and any part of the fast path that turns out to be
/// damaged, missing, or wrong falls back to resolving the real answer rather
/// than dead-ending on the recipient.
///
/// The one thing that can never be recovered is the file key: it derives from
/// the owner's wallet and drive key, exists nowhere on chain, and no query or
/// gateway call will produce it. A missing or damaged key is answered by asking
/// the recipient for one, never by retrying the network.
class SharedFileCubit extends Cubit<SharedFileState> {
  /// How many times a not-found result is retried automatically when the link
  /// asserts that the file exists.
  ///
  /// A link with a `dtx` was built from a real upload, so an all-gateway miss
  /// is far more likely to be a file that has not propagated yet than a file
  /// that is not there (`docs/FILE_SHARING_REDESIGN_PLAN.md` §2, `NOT_FOUND`).
  static const maxPropagationRetries = 3;

  final String fileId;

  /// The [SecretKey] that can be used to decode the target file.
  ///
  /// `null` if the file is public.
  final SecretKey? fileKey;

  /// Whether the link carried a file key that could not be decoded.
  ///
  /// The route parser drops such a key instead of throwing, leaving [fileKey]
  /// null, so this flag is the only thing that tells a link that arrived
  /// mangled apart from a link that never carried a key at all.
  final bool linkKeyIsDamaged;

  final ArweaveService _arweave;
  final LicenseService _licenseService;
  final ArDriveCrypto _crypto;

  /// The base delay between automatic not-found retries. Multiplied by the
  /// attempt number, so the retries back off.
  final Duration _propagationRetryDelay;

  /// The [SecretKey] the last load was attempted with.
  ///
  /// Starts as [fileKey] and is replaced by any key the user submits, so that
  /// [retry] runs with the key that was last used.
  SecretKey? _lastAttemptedFileKey;

  /// The v2 link payload, or null for a v1 link that must resolve over
  /// GraphQL exactly as it always has.
  final SharedFileLinkPayload? linkPayload;

  /// Incremented by every load. Background work started by an older load
  /// compares against it and drops its result rather than emitting over a
  /// newer one.
  int _resolution = 0;

  /// The address that wrote the file's first metadata transaction, once
  /// something has established it. See [_fileOwnerAddress].
  String? _fileOwner;

  /// How many automatic not-found retries this load has spent.
  int _propagationAttempts = 0;

  Future<void>? _backgroundWork;

  /// The longest a single network read here may take before it is abandoned.
  ///
  /// The data path has been bounded for a long time - [DataGatewayFallback]
  /// gives every fetch a request timeout, a total timeout and a hedge. The
  /// GraphQL reads that run *in front of* it had nothing: [GraphQLRetry]
  /// retries a call that fails, but sets no timeout, so a connection that
  /// errors is retried and a connection that simply hangs is not. This page
  /// would sit on its skeleton forever.
  ///
  /// Sized well above a healthy read and well below a recipient's patience.
  /// Anything that trips it lands in the load failure state, which already
  /// offers Retry.
  static const defaultReadTimeout = Duration(seconds: 15);

  /// The budget for the version history, which is a different kind of read.
  ///
  /// Every other read here fetches one thing and gates what the recipient sees;
  /// this one walks the file's whole revision history, is asked for only when
  /// the recipient opens the drawer, and blocks nothing while it runs. Holding
  /// it to the first-paint budget made a file with real history - or a slow
  /// gateway - report "version history unavailable" where it used to simply
  /// take a while.
  static const defaultHistoryTimeout = Duration(minutes: 2);

  final Duration _readTimeout;

  final Duration _historyTimeout;

  /// Bounds [future], naming [what] so a timeout is legible in the log.
  ///
  /// A [TimeoutException] is deliberately left to propagate: every caller on
  /// the critical path already handles a failed read, either by degrading to
  /// another resolution path or by emitting the failure state.
  Future<T> _bounded<T>(
    Future<T> future,
    String what, {
    Duration? timeout,
  }) {
    final budget = timeout ?? _readTimeout;

    return future.timeout(
      budget,
      onTimeout: () => throw TimeoutException(
        'Timed out after ${budget.inSeconds}s while $what',
        budget,
      ),
    );
  }

  SharedFileCubit({
    required this.fileId,
    this.fileKey,
    this.linkKeyIsDamaged = false,
    this.linkPayload,
    required arweave,
    required licenseService,
    ArDriveCrypto? crypto,
    Duration propagationRetryDelay = const Duration(seconds: 3),
    Duration readTimeout = defaultReadTimeout,
    Duration historyTimeout = defaultHistoryTimeout,
  })  : _arweave = arweave,
        _licenseService = licenseService,
        _crypto = crypto ?? ArDriveCrypto(),
        _propagationRetryDelay = propagationRetryDelay,
        _readTimeout = readTimeout,
        _historyTimeout = historyTimeout,
        // A v2 link can paint its skeleton with the real name and size before
        // a single byte has been fetched.
        super(SharedFileLoadInProgress(payload: linkPayload)) {
    loadFileDetails(fileKey);
  }

  /// The background verification, freshness and recovery work of the current
  /// load, for tests that need to observe its outcome.
  ///
  /// Nothing in the app awaits this: that it is *not* awaited is the contract.
  @visibleForTesting
  Future<void> get backgroundWork async {
    await _backgroundWork;
  }

  String getPerformedRevisionAction(FileEntity entity,
      [FileRevision? previousRevision]) {
    if (previousRevision != null) {
      if (entity.name != previousRevision.name) {
        return RevisionAction.rename;
      } else if (entity.parentFolderId != previousRevision.parentFolderId) {
        return RevisionAction.move;
      } else if (entity.dataTxId != previousRevision.dataTxId) {
        return RevisionAction.uploadNewVersion;
      } else if (entity.licenseTxId != previousRevision.licenseTxId) {
        return RevisionAction.assertLicense;
      }
    }

    return RevisionAction.create;
  }

  Future<List<FileRevision>> computeRevisionsFromEntities(
    List<FileEntity> fileEntities,
  ) async {
    late FileRevision oldestRevision;

    fileEntities.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    oldestRevision = fileEntities.first.toRevision(
      performedAction: RevisionAction.create,
    );
    // Remove oldest revision from list so we dont compute it again.
    fileEntities.removeAt(0);
    final revisions = <FileRevision>[oldestRevision];
    for (final entity in fileEntities) {
      final revisionPerformedAction = getPerformedRevisionAction(
        entity,
        revisions.last,
      );

      entity.parentFolderId = entity.parentFolderId ?? rootPath;
      final revision = entity.toRevision(
        performedAction: revisionPerformedAction,
      );

      if (revision.action.isEmpty) {
        continue;
      }

      revisions.add(revision);
    }
    // Reverse list so it is in chronological order.
    return revisions.reversed.toList();
  }

  Future<LicenseState?> fetchLicenseForRevision(
    FileRevision revision, {
    String? owner,
  }) async {
    final isComposed = revision.licenseTxId == revision.dataTxId;
    if (isComposed) {
      // License Composed
      final licenseTxs = await _arweave
          .getLicenseComposed([revision.licenseTxId!], owner: owner)
          .expand((e) => e)
          .toList();
      if (licenseTxs.isEmpty) {
        logger.e(
            'Could not find any license composed with txId: ${revision.licenseTxId}');
        return null;
      }
      final licenseComposedEntity =
          LicenseComposedEntity.fromTransaction(licenseTxs.single);
      return _licenseService.fromComposedEntity(licenseComposedEntity);
    } else {
      // License Assertion
      final licenseTxs = await _arweave
          .getLicenseAssertions([revision.licenseTxId!], owner: owner)
          .expand((e) => e)
          .toList();
      if (licenseTxs.isEmpty) {
        logger.e(
            'Could not find any license assertions with txId: ${revision.licenseTxId}');
        return null;
      }
      final licenseAssertionEntity =
          LicenseAssertionEntity.fromTransaction(licenseTxs.single);
      return _licenseService.fromAssertionEntity(licenseAssertionEntity);
    }
  }

  /// Resolves the shared file and paints it.
  ///
  /// A v1 link goes straight down the GraphQL path. A v2 link resolves per
  /// field: whatever the link carried is used, whatever it did not carry is
  /// looked up.
  Future<void> loadFileDetails(SecretKey? fileKey) async {
    if (fileId.trim().isEmpty) {
      // A link that names no file at all - `/file//view`, which the route
      // parser turns into an empty file id. No query can be built from it, so
      // nothing is asked of the network and the recipient is told the one
      // thing that is true: the link did not arrive whole.
      emit(const SharedFileLinkDamaged());
      return;
    }

    _lastAttemptedFileKey = fileKey;

    // A load the user asked for restarts the propagation budget: they are
    // entitled to another round of retries.
    _propagationAttempts = 0;

    final resolution = ++_resolution;
    final payload = linkPayload;

    if (payload == null) {
      await _resolveOverGraphQL(fileKey, resolution: resolution);
      return;
    }

    await _resolveFromPayload(payload, fileKey, resolution: resolution);
  }

  /// Runs the load again with the key that was last attempted.
  Future<void> retry() => loadFileDetails(_lastAttemptedFileKey);

  /// Loads the file's revision history.
  ///
  /// Never called during resolution: the history costs one metadata fetch per
  /// revision, which is the single most expensive thing about the first paint
  /// today. The UI calls this the first time the activity view is opened.
  ///
  /// This never touches the download target - it only fills
  /// [SharedFileLoadSuccess.activityRevisions] - so opening the activity view
  /// can never swap the file out from under the recipient.
  Future<void> loadActivity() async {
    final current = state;

    if (current is! SharedFileLoadSuccess) {
      return;
    }

    if (current.activityStatus == SharedFileActivityStatus.loading ||
        current.activityStatus == SharedFileActivityStatus.loaded) {
      return;
    }

    final resolution = _resolution;
    final fileKey = _lastAttemptedFileKey;

    emit(current.copyWith(
      activityStatus: SharedFileActivityStatus.loading,
      // The version the link named is already in hand - it is what the page is
      // showing. It renders the moment the list is opened, and the rest of the
      // history fills in around it, so expanding never costs a wait and a
      // failed lookup never empties the list.
      activityRevisions: current.activityRevisions.isEmpty
          ? [current.sharedRevision]
          : current.activityRevisions,
    ));

    try {
      final entities = await _bounded(
        _arweave.getAllFileEntitiesWithId(fileId, fileKey),
        'reading the file\'s version history',
        timeout: _historyTimeout,
      );

      if (_isStale(resolution)) {
        return;
      }

      final latest = state;

      if (latest is! SharedFileLoadSuccess) {
        return;
      }

      if (entities == null || entities.isEmpty) {
        emit(latest.copyWith(activityStatus: SharedFileActivityStatus.failed));
        return;
      }

      final revisions = await computeRevisionsFromEntities(entities);

      if (_isStale(resolution)) {
        return;
      }

      emit(latest.copyWith(
        activityRevisions: revisions,
        activityStatus: SharedFileActivityStatus.loaded,
      ));
    } catch (e, stacktrace) {
      logger.e('Failed to load the activity of the shared file', e, stacktrace);

      final latest = state;

      if (!_isStale(resolution) && latest is SharedFileLoadSuccess) {
        emit(latest.copyWith(activityStatus: SharedFileActivityStatus.failed));
      }
    }
  }

  /// Makes [revision] what the page shows and downloads.
  ///
  /// The version list's own action. [showLatestRevision] and
  /// [showSharedRevision] remain the banner's two shortcuts; this is the
  /// general case behind them, so a recipient can pick any version the file
  /// has rather than only the two the page happens to offer.
  ///
  /// The banner stays honest afterwards because "a newer version exists" is
  /// re-derived from where the selection landed: on the newest revision there
  /// is nothing newer to offer, and on any older one there is.
  ///
  /// Selecting is deliberate, so unlike the freshness check it *does* move the
  /// download target - that is the whole point of the control. Nothing moves it
  /// on the recipient's behalf.
  Future<void> showRevision(FileRevision revision) async {
    final current = state;

    if (current is! SharedFileLoadSuccess) {
      return;
    }

    // Already the target. Re-emitting would drop the license for no reason.
    if (isSameRevision(revision, current.revision)) {
      return;
    }

    final history = current.activityRevisions;
    final isNewest =
        history.isNotEmpty && isSameRevision(revision, history.first);

    emit(_withTarget(current, revision, showsLatestRevision: isNewest));

    await _fetchLicense(
      revision,
      current.ownerAddress,
      resolution: _resolution,
    );
  }

  /// Takes the file's newest revision as what the page shows and downloads.
  ///
  /// The freshness check never moves the target; it raises a flag, and the page
  /// offers what the flag says (`docs/FILE_SHARING_REDESIGN_PLAN.md`,
  /// decision 1: offer, never swap). This is the recipient accepting that
  /// offer - "Get latest" on a live link, "View latest" on a pinned one - and
  /// it is the only path on which the target moves because a newer revision
  /// exists.
  ///
  /// A pinned link is put back exactly as it was by [showSharedRevision], so
  /// nobody who was deliberately sent a pinned version can lose it by pressing
  /// this.
  ///
  /// Two things are deliberately left alone:
  ///
  /// * [SharedFileLoadSuccess.verification] is a verdict on *the link* - did it
  ///   describe the revision it named truthfully - and that question was
  ///   already answered. Showing another revision does not change the answer,
  ///   and re-running the comparison against a revision the link never
  ///   described would manufacture a mismatch out of the recipient's own
  ///   request.
  /// * [SharedFileLoadSuccess.activityRevisions] is the file's history, which
  ///   is the same history whichever revision is being shown.
  ///
  /// Does nothing when no newer revision is on offer, and nothing when the
  /// newest revision cannot be read - the page keeps the bytes it has, keeps
  /// offering, and pressing again tries again.
  Future<void> showLatestRevision() async {
    final current = state;

    if (current is! SharedFileLoadSuccess || !current.newerVersionAvailable) {
      return;
    }

    final resolution = _resolution;
    final fileKey = _lastAttemptedFileKey;

    FileEntity? latest;

    try {
      latest = await _bounded(
        _arweave.getLatestFileEntityWithId(fileId, fileKey),
        'checking for a newer revision',
      );
    } catch (e, stacktrace) {
      logger.e(
        'Failed to load the newest revision of the shared file',
        e,
        stacktrace,
      );
    }

    if (latest == null || _isStale(resolution)) {
      return;
    }

    final now = state;

    if (now is! SharedFileLoadSuccess) {
      return;
    }

    final revision = _toRevision(latest);

    if (revision == null) {
      return;
    }

    emit(_withTarget(
      now,
      revision,
      showsLatestRevision: true,
      ownerAddress: latest.ownerAddress,
    ));

    await _fetchLicense(revision, latest.ownerAddress, resolution: resolution);
  }

  /// Puts the revision the link named back as what the page shows and
  /// downloads.
  ///
  /// The way back from [showLatestRevision], so that a pinned link is never a
  /// one-way door: the version it was pinned to is one press away again, and
  /// the newer-version offer comes back with it.
  Future<void> showSharedRevision() async {
    final current = state;

    if (current is! SharedFileLoadSuccess || !current.showsLatestRevision) {
      return;
    }

    final linkRevision = current.linkRevision;

    if (linkRevision == null) {
      return;
    }

    emit(_withTarget(current, linkRevision, showsLatestRevision: false));

    await _fetchLicense(
      linkRevision,
      current.ownerAddress,
      resolution: _resolution,
    );
  }

  /// Recovers from a data transaction that no gateway will serve.
  ///
  /// Call this when the target's bytes come back 404 everywhere - the fast path
  /// hands the download a transaction id the page never fetched itself, so this
  /// is the only way the resolver hears about it.
  ///
  /// Two very different things look identical from the outside, and this tells
  /// them apart by asking the chain what the file's data transaction really is:
  ///
  /// * the chain names a *different* transaction ⇒ the link was wrong (stale,
  ///   or crafted to point at other bytes). The real revision replaces the
  ///   target and the verification verdict drops to
  ///   [LinkVerification.mismatch];
  /// * the chain agrees, or has not seen the file at all ⇒ the file was
  ///   uploaded recently and has not propagated. That is the not-found path,
  ///   with its automatic retries.
  Future<void> recoverMissingData() async {
    final current = state;

    if (current is! SharedFileLoadSuccess) {
      return;
    }

    await _recoverMissingData(
      current.revision.dataTxId,
      _lastAttemptedFileKey,
      resolution: _resolution,
    );
  }

  Future<void> launchPreview(TxID dataTxId) =>
      openUrl(url: '${_arweave.client.api.gatewayUrl}/$dataTxId');

  Future<void> submit(String fileKeyBase64) async {
    // Whatever the previous load left running in the background belongs to a
    // key that is no longer the one being tried.
    _resolution++;

    emit(SharedFileLoadInProgress(payload: linkPayload));

    final SecretKey fileKey;

    try {
      fileKey = SecretKey(decodeBase64ToBytes(fileKeyBase64));
    } catch (e) {
      // The reason, never the exception object: the `source` of the
      // `FormatException` a base64 decoder throws is the key itself, and
      // `toString()` prints a window of it into a log the user can export.
      logger.e(
        'Failed to decode the submitted file key: '
        '${e is FormatException ? e.message : e.runtimeType}',
      );
      emit(SharedFileKeyInvalid(payload: linkPayload));
      return;
    }

    _lastAttemptedFileKey = fileKey;

    final metadataTxId = linkPayload?.metadataTxId;

    try {
      if (metadataTxId != null) {
        // The link names the exact revision that was shared, so the key is
        // tried against it directly: one lookup by transaction id instead of an
        // owner probe followed by a latest-revision query.
        final shared = await _bounded(
          _fetchSharedRevision(metadataTxId, fileKey),
          'trying the key against the revision the link names',
        );

        if (shared == null) {
          // The link's metadata transaction is not on the network. The key may
          // still be perfectly good, so fall back to resolving the file the
          // long way rather than blaming the key.
          final file = await _bounded(
            _arweave.getLatestFileEntityWithId(fileId, fileKey),
            'looking up the newest revision to try the key against',
          );

          if (file == null) {
            emit(SharedFileKeyInvalid(payload: linkPayload));
            return;
          }
        }
      } else {
        final file = await _arweave.getLatestFileEntityWithId(fileId, fileKey);

        if (file == null) {
          // The file exists - it is what the user is looking at - so the key is
          // what could not decrypt its metadata.
          emit(SharedFileKeyInvalid(payload: linkPayload));
          return;
        }
      }
    } on EntityTransactionParseException {
      // The metadata is there and this key does not open it.
      emit(SharedFileKeyInvalid(payload: linkPayload));
      return;
    } catch (e, stacktrace) {
      logger.e('Failed to submit file key', e, stacktrace);
      emit(SharedFileLoadFailure());
      return;
    }

    await loadFileDetails(fileKey);
  }

  // ---------------------------------------------------------------------------
  // Resolution
  // ---------------------------------------------------------------------------

  /// Resolves a v2 link, using every field it carried and looking up only what
  /// it did not.
  Future<void> _resolveFromPayload(
    SharedFileLinkPayload payload,
    SecretKey? fileKey, {
    required int resolution,
  }) async {
    emit(SharedFileLoadInProgress(payload: payload));

    if (payload.cipher != null && fileKey == null) {
      // The link says the file is encrypted and no key travelled with it. No
      // amount of network access can produce a file key, so this is answered
      // without touching the network, and it is answered instantly.
      _emitLocked(payload);
      return;
    }

    if (payload.dataTxId != null) {
      // The fast path: everything the header needs is either in the link or is
      // a placeholder that the background metadata resolution fills in. No
      // GraphQL runs before this paint.
      emit(_successFromPayload(payload, fileKey));

      // Scheduled rather than started: the paint is delivered first, and not a
      // single request goes out before it.
      _backgroundWork = Future(
        () => _runBackgroundWork(payload, fileKey, resolution: resolution),
      );

      unawaited(_backgroundWork);
      return;
    }

    // No usable data transaction survived the link. `dtx` was absent, or it
    // arrived malformed and the parser dropped it; both mean the same thing
    // here, and both are recovered the same way.
    if (payload.metadataTxId != null) {
      // The link still names the revision that was shared, which resolves it
      // in one lookup by id - no owner probe, no revision enumeration, and it
      // keeps a pinned link pinned.
      final resolved = await _resolveFromMetadataTx(
        payload,
        fileKey,
        resolution: resolution,
      );

      if (resolved) {
        return;
      }
    }

    await _resolveOverGraphQL(fileKey, resolution: resolution);
  }

  /// Resolves the shared revision from the link's `mtx`.
  ///
  /// Returns `false` when the metadata could not be turned into a revision, in
  /// which case the caller falls back to full GraphQL resolution.
  Future<bool> _resolveFromMetadataTx(
    SharedFileLinkPayload payload,
    SecretKey? fileKey, {
    required int resolution,
  }) async {
    final metadataTxId = payload.metadataTxId!;

    _SharedRevision? shared;

    try {
      shared = await _bounded(
        _fetchSharedRevision(metadataTxId, fileKey),
        'reading the metadata transaction the link names',
      );
    } on EntityTransactionParseException {
      if (_isStale(resolution)) {
        return true;
      }

      if (fileKey == null) {
        // Metadata that will not parse without a key in play is not a key
        // problem. Resolve the file the long way instead of blaming a key that
        // was never used.
        return false;
      }

      // The metadata is encrypted and the key at hand does not open it.
      emit(SharedFileKeyInvalid(payload: payload));
      return true;
    } catch (e, stacktrace) {
      logger.e(
        'Failed to resolve a shared file from the metadata transaction its '
        'link names',
        e,
        stacktrace,
      );

      return false;
    }

    if (_isStale(resolution)) {
      return true;
    }

    if (shared == null) {
      // The link names a metadata transaction the network does not have.
      return false;
    }

    if (shared.isLocked) {
      // The link never said the file was encrypted - `c` was absent, or was
      // dropped as malformed - but its metadata is.
      _emitLocked(payload);
      return true;
    }

    final entity = shared.entity!;
    final metadataOwner = shared.ownerAddress;

    if (entity.id != fileId) {
      // The metadata transaction belongs to a different file. Nothing in this
      // link can be trusted after that, so the file id in the route - the one
      // thing the recipient actually asked for - is resolved from scratch.
      logger.w(
        'A shared file link names a metadata transaction that belongs to '
        'another file. Resolving the file over GraphQL instead.',
      );

      await _resolveOverGraphQL(
        fileKey,
        resolution: resolution,
        verificationOverride: LinkVerification.mismatch,
      );

      return true;
    }

    final revision = _toRevision(entity);

    if (revision == null) {
      return false;
    }

    emit(SharedFileLoadSuccess(
      fileRevisions: [revision],
      fileKey: fileKey,
      ownerAddress: entity.ownerAddress,
      payload: payload,
      // This metadata was fetched by id, so nothing has established yet that
      // the file's owner wrote it. The verdict waits for [_confirmAuthorship];
      // it is never taken from the metadata's agreement with the link alone.
      verification: LinkVerification.pending,
      isPinned: payload.isPinned,
      newerVersionAvailable: false,
    ));

    _backgroundWork = Future(
      () => Future.wait([
        _fetchLicense(revision, entity.ownerAddress, resolution: resolution),
        // The freshness lookup is owner scoped, so the entity it returns also
        // answers who owns the file - one lookup for both questions.
        _checkFreshness(fileKey, resolution: resolution).then(
          (latest) => _confirmAuthorship(
            payload,
            revision,
            metadataOwner,
            fileKey,
            knownOwner: latest?.ownerAddress,
            resolution: resolution,
          ),
        ),
      ]),
    );

    unawaited(_backgroundWork);

    return true;
  }

  /// Today's resolution path, unchanged: privacy probe, then every revision of
  /// the file, then the license of the newest one.
  ///
  /// This is what a v1 link has always done, and what any v2 link falls back to
  /// when nothing usable survived its payload.
  ///
  /// [isRecovery] marks the runs that happen *behind* an already painted page,
  /// when something about the link turned out to be wrong. Those runs never
  /// show a spinner and never tear the page down: if the file cannot be
  /// resolved after all, the recipient keeps the page they have, with the
  /// verification badge saying what is known about it.
  Future<void> _resolveOverGraphQL(
    SecretKey? fileKey, {
    required int resolution,
    bool announceProgress = true,
    bool isRecovery = false,
    LinkVerification? verificationOverride,
  }) async {
    try {
      if (announceProgress && !isRecovery) {
        emit(SharedFileLoadInProgress(payload: linkPayload));
      }

      final privacy = await _bounded(
        _arweave.getFilePrivacyForId(fileId),
        'looking up whether the file is private',
      );

      if (_isStale(resolution)) {
        return;
      }

      if (fileKey == null && privacy == DrivePrivacyTag.private) {
        _emitLocked(linkPayload);
        return;
      }
      final allEntities = await _bounded(
        _arweave.getAllFileEntitiesWithId(fileId, fileKey),
        'reading the file\'s revisions',
      );

      if (_isStale(resolution)) {
        return;
      }

      if (allEntities != null) {
        // Get owner address from the oldest FileEntity (original uploader)
        // We need to get this before converting to revisions since FileRevision doesn't have ownerAddress
        String? ownerAddress;
        if (allEntities.isNotEmpty) {
          // Sort entities by creation date to find the original
          allEntities.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          // Get the owner address from the oldest entity (original uploader)
          ownerAddress = allEntities.first.ownerAddress;
        }

        final revisions = await computeRevisionsFromEntities(allEntities);

        if (_isStale(resolution)) {
          return;
        }

        // revisions are in reverse chronological order, so first is most recent
        final target = _targetRevision(revisions);
        final latestLicense = target.licenseTxId != null
            ? await _bounded(
                fetchLicenseForRevision(target, owner: ownerAddress),
                'reading the file\'s license',
              )
            : null;

        if (_isStale(resolution)) {
          return;
        }

        final current = state;

        if (isRecovery &&
            current is SharedFileLoadSuccess &&
            current.showsLatestRevision) {
          // Recovery runs behind a page the recipient is already using, and
          // this one started before they asked for the newest revision. Their
          // choice stands; only the verdict on the link is taken from here.
          _emitVerification(
            verificationOverride ?? _verifyAgainst(revisions, ownerAddress),
            resolution: resolution,
          );
          return;
        }

        emit(SharedFileLoadSuccess(
          // A v1 link has always handed the whole history to the page, and
          // still does. A v2 link keeps its target at `first` and takes the
          // history through the lazy activity load instead.
          fileRevisions: linkPayload == null ? revisions : [target],
          fileKey: fileKey,
          latestLicense: latestLicense,
          ownerAddress: ownerAddress,
          payload: linkPayload,
          verification:
              verificationOverride ?? _verifyAgainst(revisions, ownerAddress),
          newerVersionAvailable: _hasNewerThan(target, revisions),
          isPinned: linkPayload?.isPinned ?? false,
          activityRevisions: revisions,
          activityStatus: SharedFileActivityStatus.loaded,
        ));
        return;
      }

      // No revision could be read. When the privacy probe resolved the file as
      // private and a key was supplied, it is the key that is wrong and not the
      // file that is missing: every revision failed to decrypt and was skipped.
      if (fileKey != null && privacy == DrivePrivacyTag.private) {
        emit(SharedFileKeyInvalid(payload: linkPayload));
        return;
      }

      if (isRecovery) {
        // GraphQL knows nothing about this file id. That is not a reason to
        // take away a page the link already painted - the bytes it points at
        // may well be fetchable - so only the verdict changes.
        _emitVerification(
          verificationOverride ?? LinkVerification.unavailable,
          resolution: resolution,
        );
        return;
      }

      await _notFound(fileKey, resolution: resolution);
    } catch (e, stacktrace) {
      logger.e('Failed to load the details of the shared file', e, stacktrace);

      if (_isStale(resolution)) {
        return;
      }

      if (isRecovery) {
        _emitVerification(
          verificationOverride ?? LinkVerification.unavailable,
          resolution: resolution,
        );
        return;
      }

      emit(SharedFileLoadFailure());
    }
  }

  /// The revision the page acts on.
  ///
  /// Newest by default (decision 1). A pinned link keeps the revision it was
  /// made from, when that revision is still among the file's history.
  FileRevision _targetRevision(List<FileRevision> revisions) {
    final payload = linkPayload;

    if (payload == null || !payload.isPinned || payload.metadataTxId == null) {
      return revisions.first;
    }

    return revisions.firstWhere(
      (revision) => revision.metadataTxId == payload.metadataTxId,
      orElse: () => revisions.first,
    );
  }

  bool _hasNewerThan(FileRevision target, List<FileRevision> revisions) =>
      revisions.first.metadataTxId != target.metadataTxId;

  /// The verification verdict for a link whose file was resolved over GraphQL.
  ///
  /// The revisions come from the chain, so the link's claims can be checked
  /// against the revision it says it shared. When that revision is not among
  /// them, the link is naming a metadata transaction that is not part of this
  /// file - which is exactly what a crafted link looks like.
  LinkVerification _verifyAgainst(
    List<FileRevision> revisions,
    String? ownerAddress,
  ) {
    final payload = linkPayload;

    if (payload == null || payload.metadataTxId == null) {
      return LinkVerification.unavailable;
    }

    final shared = revisions.firstWhereOrNull(
      (revision) => revision.metadataTxId == payload.metadataTxId,
    );

    if (shared == null) {
      logger.w(
        'A shared file link names a metadata transaction that is not a '
        'revision of the file it points at.',
      );

      return LinkVerification.mismatch;
    }

    return _reconcile(payload, shared, ownerAddress);
  }

  // ---------------------------------------------------------------------------
  // Background work: verification, freshness, license
  // ---------------------------------------------------------------------------

  /// Everything the page does *after* it has been painted from the link.
  ///
  /// Two questions are outstanding at that point - is there a newer revision,
  /// and was the link telling the truth - and in the common case one lookup
  /// answers both: the revision a link shares is usually still the file's
  /// newest, so the entity that settles the freshness question is also the
  /// record the link's claims are checked against. A second fetch is needed
  /// only when a newer revision has appeared since the link was made.
  Future<void> _runBackgroundWork(
    SharedFileLinkPayload payload,
    SecretKey? fileKey, {
    required int resolution,
  }) async {
    final metadataTxId = payload.metadataTxId;

    FileEntity? latest;

    try {
      // Bounded like every other read that gates what the recipient sees.
      // Unbounded, a gateway that accepts the connection and then says nothing
      // leaves `detailsAreResolved` false forever - and the desktop pane sits
      // on "Loading file details..." with no preview and no way out, because
      // the preview needs a drive id that only this read can supply.
      latest = await _bounded(
        _arweave.getLatestFileEntityWithId(fileId, fileKey),
        'looking up the newest revision',
      );
    } catch (e, stacktrace) {
      // A freshness check that fails changes nothing about the file in hand.
      logger.e(
        'Failed to look up the newest revision of the shared file',
        e,
        stacktrace,
      );
    }

    if (_isStale(resolution)) {
      return;
    }

    if (latest != null) {
      final sharesTheNewestRevision = metadataTxId == null
          // A link that carried no `mtx` has nothing but its data transaction
          // to compare with.
          ? latest.dataTxId == payload.dataTxId
          : latest.txId == metadataTxId;

      if (sharesTheNewestRevision) {
        // The link named the file's own newest revision, so this entity is the
        // owner's own metadata by construction.
        await _adoptResolvedRevision(payload, latest, resolution: resolution);
        return;
      }

      _markNewerVersionAvailable(resolution: resolution);
    } else if (metadataTxId == null) {
      // Nothing corroborated the link at all: the newest revision could not be
      // read, and there is no metadata transaction to check against. One of the
      // things that hides in here is a private file whose link never said so -
      // `c` absent or dropped, and no key - which has painted a page that can
      // never download. Resolving from the file id is the only thing left that
      // can tell that apart from a healthy public file.
      await _resolveOverGraphQL(
        fileKey,
        resolution: resolution,
        isRecovery: true,
        verificationOverride: LinkVerification.unavailable,
      );
      return;
    }

    // Either a newer revision exists, or the newest one could not be read. The
    // revision the link actually shared still has to be checked, and that means
    // fetching the metadata transaction it names.
    await _verifyLink(
      payload,
      fileKey,
      resolution: resolution,
      // The newest revision came out of an owner-scoped query, so when there
      // was one it has already answered who owns the file.
      knownOwner: latest?.ownerAddress,
    );
  }

  /// Takes the file's own record as what the page shows and downloads.
  ///
  /// The link's claims stay on the state for the UI to compare against, but
  /// from here on the chain is the authority - including for the download
  /// target, which is the whole point of noticing a mismatch at all.
  ///
  /// [authorshipIsConfirmed] says whether [entity] is known to have been
  /// written by the file's owner. It is `true` for anything an owner-scoped
  /// query returned, and `false` when metadata fetched by id could not be
  /// attributed - in which case the page keeps what it resolved and the badge
  /// stops short of endorsing it.
  Future<void> _adoptResolvedRevision(
    SharedFileLinkPayload payload,
    FileEntity entity, {
    required int resolution,
    bool authorshipIsConfirmed = true,
  }) async {
    final revision = _toRevision(entity);

    if (revision == null) {
      _emitVerification(LinkVerification.unavailable, resolution: resolution);
      return;
    }

    final current = state;

    if (current is! SharedFileLoadSuccess) {
      return;
    }

    final verification = payload.metadataTxId == null || !authorshipIsConfirmed
        // Without an `mtx` there is no claim about *which* revision was
        // shared, and without a confirmed author there is nothing worth
        // comparing it against. Neither amounts to a verified link.
        ? LinkVerification.unavailable
        : _reconcile(payload, revision, entity.ownerAddress);

    if (current.showsLatestRevision) {
      // The recipient asked for the newest revision while this was in flight.
      // A background job never overrules that: the verdict on the link is still
      // worth having, the revision it was about is not.
      emit(current.copyWith(verification: verification));
      return;
    }

    emit(current.copyWith(
      fileRevisions: [revision],
      ownerAddress: entity.ownerAddress,
      verification: verification,
      detailsAreResolved: true,
    ));

    await _fetchLicense(revision, entity.ownerAddress, resolution: resolution);
  }

  void _markNewerVersionAvailable({required int resolution}) {
    if (_isStale(resolution)) {
      return;
    }

    final current = state;

    // Nothing to offer once the recipient is already looking at the newest
    // revision - and offering it again there would read as a third version.
    if (current is SharedFileLoadSuccess && !current.showsLatestRevision) {
      emit(current.copyWith(newerVersionAvailable: true));
    }
  }

  /// Checks what the link claims against the file's own metadata.
  ///
  /// Runs only after the page has been painted, and never blocks it. The link
  /// asserts its own contents, so a disagreement means the link is describing
  /// something other than the file it points at: from that moment the chain is
  /// what is shown and downloaded, and the verdict tells the recipient why the
  /// page does not match the link they were sent.
  ///
  /// [knownOwner] is the file's owner when the caller already has it from an
  /// owner-scoped query, which spares the first-writer probe.
  Future<void> _verifyLink(
    SharedFileLinkPayload payload,
    SecretKey? fileKey, {
    required int resolution,
    String? knownOwner,
  }) async {
    final metadataTxId = payload.metadataTxId;

    if (metadataTxId == null) {
      // Nothing to check against; already reported as unavailable.
      return;
    }

    _SharedRevision? shared;

    try {
      shared = await _fetchSharedRevision(metadataTxId, fileKey);
    } on EntityTransactionParseException {
      if (_isStale(resolution)) {
        return;
      }

      if (fileKey != null) {
        // The link's own metadata will not open with the key in hand. The file
        // is there, so this is the locked case and never a missing file.
        emit(SharedFileKeyInvalid(payload: payload));
        return;
      }

      // Unreadable metadata with no key in play says nothing about the file
      // itself. Ask the chain rather than the link.
      await _resolveOverGraphQL(
        fileKey,
        resolution: resolution,
        isRecovery: true,
        verificationOverride: LinkVerification.unavailable,
      );
      return;
    } catch (e, stacktrace) {
      logger.e(
        'Failed to verify a shared file link against its metadata',
        e,
        stacktrace,
      );

      _emitVerification(LinkVerification.unavailable, resolution: resolution);
      return;
    }

    if (_isStale(resolution)) {
      return;
    }

    if (shared == null) {
      // The metadata transaction the link names is not on the network, so
      // nothing it claims can be trusted. Resolve the file from its id.
      logger.w(
        'The metadata transaction of a shared file link could not be found. '
        'Resolving the file over GraphQL instead.',
      );

      await _resolveOverGraphQL(
        fileKey,
        resolution: resolution,
        isRecovery: true,
        verificationOverride: LinkVerification.unavailable,
      );
      return;
    }

    if (shared.isLocked) {
      // The link did not say the file was encrypted - `c` was absent, or was
      // dropped as malformed - but its metadata is. Locked is the honest state,
      // and the name and size the link carried are still shown on it.
      _emitLocked(payload);
      return;
    }

    final entity = shared.entity!;

    if (entity.id != fileId) {
      logger.w(
        'A shared file link names a metadata transaction that belongs to '
        'another file. Resolving the file over GraphQL instead.',
      );

      await _resolveOverGraphQL(
        fileKey,
        resolution: resolution,
        isRecovery: true,
        verificationOverride: LinkVerification.mismatch,
      );
      return;
    }

    // The metadata carries the right file id, but it was fetched by
    // transaction id and anyone can post a transaction. Until its author is
    // the file's owner it describes nothing (see [_fileOwnerAddress]).
    final fileOwner = await _fileOwnerAddress(knownOwner: knownOwner);

    if (_isStale(resolution)) {
      return;
    }

    if (fileOwner != null && shared.ownerAddress != fileOwner) {
      logger.w(
        'A shared file link names a metadata transaction that the file\'s '
        'owner did not write. Resolving the file over GraphQL instead.',
      );

      await _resolveOverGraphQL(
        fileKey,
        resolution: resolution,
        isRecovery: true,
        verificationOverride: LinkVerification.mismatch,
      );
      return;
    }

    // The resolved revision is what the page shows from here on, whatever the
    // verdict: when it agrees with the link nothing visible changes, and when
    // it does not, the file's own record is the one worth showing.
    await _adoptResolvedRevision(
      payload,
      entity,
      resolution: resolution,
      authorshipIsConfirmed: fileOwner != null,
    );
  }

  /// Settles the verdict on a link whose revision came out of its own `mtx`.
  ///
  /// Nothing has established at that point that the file's owner wrote that
  /// metadata - it was fetched by transaction id, which anyone can mint. A
  /// stranger's metadata is not this file's record however well formed it is,
  /// so the file is resolved from its id instead and the link is reported as
  /// what it is.
  Future<void> _confirmAuthorship(
    SharedFileLinkPayload payload,
    FileRevision revision,
    String? metadataOwner,
    SecretKey? fileKey, {
    String? knownOwner,
    required int resolution,
  }) async {
    final fileOwner = await _fileOwnerAddress(knownOwner: knownOwner);

    if (_isStale(resolution)) {
      return;
    }

    if (fileOwner == null) {
      // Nobody could say who owns the file. The page keeps the revision it
      // resolved; the badge stops short of endorsing it.
      _emitVerification(LinkVerification.unavailable, resolution: resolution);
      return;
    }

    if (metadataOwner != fileOwner) {
      logger.w(
        'A shared file link names a metadata transaction that the file\'s '
        'owner did not write. Resolving the file over GraphQL instead.',
      );

      await _resolveOverGraphQL(
        fileKey,
        resolution: resolution,
        isRecovery: true,
        verificationOverride: LinkVerification.mismatch,
      );
      return;
    }

    _emitVerification(
      _reconcile(payload, revision, metadataOwner),
      resolution: resolution,
    );
  }

  /// The address that wrote the file's first metadata transaction - the only
  /// address whose ArFS metadata describes this file.
  ///
  /// Every GraphQL path resolves this first and scopes its queries to it
  /// (`ArweaveService.getOwnerForFileEntityWithId`). The `mtx` routes are the
  /// ones that skip the probe, because `getTransactionDetails` resolves a
  /// transaction by id alone: anyone can post ArFS metadata tagged with a
  /// `File-Id` that is already circulating, and nothing about the transaction
  /// itself says whether it belongs to the file the recipient asked for. So the
  /// probe happens here instead - behind the paint, never in front of it, and
  /// only when [knownOwner] did not already answer it.
  ///
  /// Returns `null` when the owner could not be established. That is never a
  /// verdict of its own: a question that could not be answered leaves the link
  /// unverified, and never verified.
  Future<String?> _fileOwnerAddress({String? knownOwner}) async {
    if (knownOwner != null) {
      return _fileOwner = knownOwner;
    }

    final resolved = _fileOwner;

    if (resolved != null) {
      // The first writer of a file id never changes, so this is asked once.
      return resolved;
    }

    try {
      return _fileOwner = await _bounded(
        _arweave.getOwnerForFileEntityWithId(fileId),
        'resolving the file owner',
      );
    } catch (e, stacktrace) {
      logger.e(
        'Failed to resolve the owner of the shared file',
        e,
        stacktrace,
      );

      return null;
    }
  }

  /// Looks for a revision newer than the one being shown.
  ///
  /// One lookup, off the critical path, and it only ever sets a flag: the page
  /// offers the newer revision and never swaps to it, on a pinned link or a
  /// live one (decision 1).
  ///
  /// Returns the newest revision it read, which is owner scoped and therefore
  /// also answers who owns the file, or `null` when it could not be read.
  Future<FileEntity?> _checkFreshness(
    SecretKey? fileKey, {
    required int resolution,
  }) async {
    try {
      final latest = await _arweave.getLatestFileEntityWithId(fileId, fileKey);

      if (latest == null || _isStale(resolution)) {
        return latest;
      }

      final current = state;

      if (current is! SharedFileLoadSuccess) {
        return latest;
      }

      final target = current.revision;
      final isNewer =
          (target.metadataTxId.isNotEmpty && latest.txId != target.metadataTxId)
              // A link that carried no `mtx` has nothing but the data
              // transaction to compare.
              ||
              (latest.dataTxId != null && latest.dataTxId != target.dataTxId);

      if (isNewer) {
        emit(current.copyWith(newerVersionAvailable: true));
      }

      return latest;
    } catch (e, stacktrace) {
      // A freshness check that fails changes nothing about the file in hand.
      logger.e(
        'Failed to check whether a newer revision of the shared file exists',
        e,
        stacktrace,
      );

      return null;
    }
  }

  Future<void> _fetchLicense(
    FileRevision revision,
    String? ownerAddress, {
    required int resolution,
  }) async {
    if (revision.licenseTxId == null) {
      return;
    }

    try {
      final license = await fetchLicenseForRevision(
        revision,
        owner: ownerAddress,
      );

      if (license == null || _isStale(resolution)) {
        return;
      }

      final current = state;

      if (current is SharedFileLoadSuccess) {
        emit(current.copyWith(latestLicense: license));
      }
    } catch (e, stacktrace) {
      logger.e('Failed to load the license of the shared file', e, stacktrace);
    }
  }

  // ---------------------------------------------------------------------------
  // Not found, and files that are simply not there yet
  // ---------------------------------------------------------------------------

  Future<void> _notFound(
    SecretKey? fileKey, {
    required int resolution,
  }) async {
    // A link that names a transaction was built from a real upload, so an
    // empty network is far more likely to be a file that has not propagated
    // than a file that is not there. A v1 link whose owner probe came back
    // empty is the other case entirely, and keeps saying that the file does not
    // exist.
    final payload = linkPayload;
    final assertsExistence = payload != null &&
        (payload.dataTxId != null || payload.metadataTxId != null);

    if (!assertsExistence || _propagationAttempts >= maxPropagationRetries) {
      emit(SharedFileNotFound(
        retryAttempt: _propagationAttempts,
        mayStillBePropagating: false,
      ));
      return;
    }

    _propagationAttempts++;

    emit(SharedFileNotFound(
      retryAttempt: _propagationAttempts,
      mayStillBePropagating: true,
    ));

    await Future.delayed(_propagationRetryDelay * _propagationAttempts);

    if (_isStale(resolution)) {
      return;
    }

    // Retrying without the spinner: the card is showing a countdown, and
    // replacing it with a skeleton on every cycle would be a flicker, not
    // progress.
    await _resolveOverGraphQL(
      fileKey,
      resolution: resolution,
      announceProgress: false,
    );
  }

  Future<void> _recoverMissingData(
    String assertedDataTxId,
    SecretKey? fileKey, {
    required int resolution,
  }) async {
    _SharedRevision? shared;

    try {
      shared = await _resolveTargetRevision(fileKey);
    } catch (e, stacktrace) {
      logger.e(
        'Failed to re-resolve the data transaction of the shared file',
        e,
        stacktrace,
      );
    }

    if (_isStale(resolution)) {
      return;
    }

    final entity = shared?.entity;
    final revision = entity == null ? null : _toRevision(entity);

    if (revision != null && revision.dataTxId != assertedDataTxId) {
      // The chain names different bytes than the link did. The link is wrong,
      // innocently or otherwise, and the file's own record wins.
      logger.w(
        'The data transaction a shared file link asserts is not the one the '
        'file names. Using the file\'s record instead.',
      );

      emit(SharedFileLoadSuccess(
        fileRevisions: [revision],
        fileKey: fileKey,
        ownerAddress: entity!.ownerAddress,
        payload: linkPayload,
        verification: LinkVerification.mismatch,
        isPinned: linkPayload?.isPinned ?? false,
      ));
      return;
    }

    // Either the chain agrees with the link, or it has not seen the file at
    // all. Both say the same thing: recently uploaded, not spread yet.
    if (_propagationAttempts >= maxPropagationRetries) {
      emit(SharedFileNotFound(
        retryAttempt: _propagationAttempts,
        mayStillBePropagating: false,
      ));
      return;
    }

    _propagationAttempts++;

    emit(SharedFileNotFound(
      retryAttempt: _propagationAttempts,
      mayStillBePropagating: true,
    ));

    await Future.delayed(_propagationRetryDelay * _propagationAttempts);

    if (_isStale(resolution)) {
      return;
    }

    await _recoverMissingData(
      assertedDataTxId,
      fileKey,
      resolution: resolution,
    );
  }

  /// Resolves the revision the page should be showing, cheapest route first.
  Future<_SharedRevision?> _resolveTargetRevision(SecretKey? fileKey) async {
    final metadataTxId = linkPayload?.metadataTxId;

    if (metadataTxId != null) {
      final shared = await _fetchSharedRevision(metadataTxId, fileKey);

      if (shared != null && shared.entity != null) {
        return shared;
      }
    }

    final latest = await _arweave.getLatestFileEntityWithId(fileId, fileKey);

    if (latest == null) {
      return null;
    }

    return _SharedRevision(
      entity: latest,
      ownerAddress: latest.ownerAddress,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Fetches the revision a metadata transaction describes.
  ///
  /// One transaction lookup by id and one data fetch - no owner probe, no
  /// revision enumeration. Returns `null` when the transaction cannot be found,
  /// which means the link's `mtx` is wrong and the caller has to resolve the
  /// file the long way. Throws [EntityTransactionParseException] when the
  /// metadata is there but cannot be read with [fileKey].
  Future<_SharedRevision?> _fetchSharedRevision(
    String metadataTxId,
    SecretKey? fileKey,
  ) async {
    final transaction = await _bounded(
      _arweave.getTransactionDetails(metadataTxId),
      'reading the shared revision\'s metadata transaction',
    );

    if (transaction == null) {
      return null;
    }

    final ownerAddress = transaction.owner.address;

    if (fileKey == null && transaction.getTag(EntityTag.cipherIv) != null) {
      // Encrypted metadata and no key. Nothing on chain can produce one, so
      // this is reported, never retried.
      return _SharedRevision(ownerAddress: ownerAddress, isLocked: true);
    }

    final data = await _arweave.getEntityDataFromNetwork(txId: metadataTxId);

    final entity = await FileEntity.fromTransaction(
      transaction,
      data,
      fileKey: fileKey,
      crypto: _crypto,
    );

    return _SharedRevision(entity: entity, ownerAddress: ownerAddress);
  }

  /// The state that shows [revision] and downloads it.
  ///
  /// The one place where a revision the *recipient* chose becomes the page's
  /// target, so that everything which belongs to a revision moves with it - and
  /// so that the revision the link named is remembered, both to go back to and
  /// to mark in the version history.
  SharedFileLoadSuccess _withTarget(
    SharedFileLoadSuccess current,
    FileRevision revision, {
    required bool showsLatestRevision,
    String? ownerAddress,
  }) =>
      SharedFileLoadSuccess(
        fileRevisions: [revision],
        fileKey: current.fileKey,
        // A license belongs to the revision that asserted it, so it does not
        // survive the swap; the caller fetches the new target's own. This is
        // why the state is built field by field: `copyWith` cannot un-set it.
        latestLicense: null,
        ownerAddress: ownerAddress ?? current.ownerAddress,
        payload: current.payload,
        verification: current.verification,
        // Showing the newest revision is the offer being taken; showing the
        // link's revision again is the offer coming back.
        newerVersionAvailable: !showsLatestRevision,
        isPinned: current.isPinned,
        detailsAreResolved: _isResolved(revision),
        activityRevisions: current.activityRevisions,
        activityStatus: current.activityStatus,
        linkRevision: current.linkRevision ?? current.revision,
        showsLatestRevision: showsLatestRevision,
      );

  /// Whether a revision came from the file's own metadata rather than from the
  /// link.
  ///
  /// Nothing in a link carries a drive id - it would leak the sharer's drive
  /// for no benefit to the recipient (see [_revisionFromPayload]) - so an empty
  /// one is exactly what marks a revision the page painted from the link alone.
  bool _isResolved(FileRevision revision) => revision.driveId.isNotEmpty;

  /// The state a link paints before anything has been fetched.
  SharedFileLoadSuccess _successFromPayload(
    SharedFileLinkPayload payload,
    SecretKey? fileKey,
  ) =>
      SharedFileLoadSuccess(
        fileRevisions: [_revisionFromPayload(payload)],
        fileKey: fileKey,
        ownerAddress: payload.ownerAddress,
        payload: payload,
        // A link without `mtx` can never be checked against anything.
        verification: payload.metadataTxId == null
            ? LinkVerification.unavailable
            : LinkVerification.pending,
        isPinned: payload.isPinned,
        detailsAreResolved: false,
      );

  /// Turns what the link carried into the revision the page renders.
  ///
  /// Fields the link did not carry are placeholders - an empty name, a zero
  /// size, the epoch - flagged by [SharedFileLoadSuccess.detailsAreResolved] so
  /// that the UI shows its generic copy for them rather than a wrong value.
  /// They are filled in by the background metadata resolution.
  FileRevision _revisionFromPayload(SharedFileLinkPayload payload) =>
      FileRevision(
        fileId: fileId,
        // Neither travels in a link: nothing on the recipient's page needs the
        // file's place in its drive, and putting it in the link would leak the
        // sharer's folder structure.
        driveId: '',
        parentFolderId: '',
        name: payload.name ?? '',
        size: payload.size ?? 0,
        lastModifiedDate: unknownDate,
        dateCreated: unknownDate,
        metadataTxId: payload.metadataTxId ?? '',
        dataTxId: payload.dataTxId!,
        dataContentType: payload.contentType,
        bundledIn: payload.bundledInTxId,
        action: RevisionAction.create,
        isHidden: false,
      );

  FileRevision? _toRevision(FileEntity entity) {
    try {
      entity.parentFolderId ??= rootPath;

      return entity.toRevision(performedAction: RevisionAction.create);
    } catch (e, stacktrace) {
      // `toRevision` asserts the fields ArFS requires. Metadata that is missing
      // one of them is metadata this page cannot render.
      logger.e(
        'The metadata of the shared file is missing required fields',
        e,
        stacktrace,
      );

      return null;
    }
  }

  /// Compares what the link claims with what the file's record says.
  ///
  /// Only the fields the link actually asserted are compared - an absent field
  /// claims nothing and cannot disagree with anything. Field *names* are
  /// logged; values are not, because a private file's name and content type are
  /// secrets.
  ///
  /// A link that asserted nothing at all is [LinkVerification.unavailable] and
  /// never [LinkVerification.verified]: there was nothing about the file to
  /// check, so an empty list of disagreements is silence rather than a result.
  ///
  /// [ownerAddress] is the address that wrote the record being compared
  /// against, which callers establish as the file's own owner first - see
  /// [_fileOwnerAddress].
  LinkVerification _reconcile(
    SharedFileLinkPayload payload,
    FileRevision revision,
    String? ownerAddress,
  ) {
    final disagreements = <String>[];
    var claims = 0;

    void compare(String field, Object? claimed, Object? actual) {
      if (claimed == null) {
        return;
      }

      claims++;

      if (claimed != actual) {
        disagreements.add(field);
      }
    }

    compare(SharedFileLinkParams.dataTxId, payload.dataTxId, revision.dataTxId);
    compare(SharedFileLinkParams.name, payload.name, revision.name);
    compare(SharedFileLinkParams.size, payload.size, revision.size);
    compare(
      SharedFileLinkParams.contentType,
      payload.contentType,
      revision.dataContentType,
    );
    compare(SharedFileLinkParams.owner, payload.ownerAddress, ownerAddress);

    if (disagreements.isNotEmpty) {
      logger.w(
        'A shared file link disagrees with the file\'s record on: '
        '${disagreements.join(', ')}',
      );

      return LinkVerification.mismatch;
    }

    // A link carrying nothing but `mtx` describes the file in no way at all.
    // Reporting that as verified would put an affirmative badge on a check
    // that had nothing to run against.
    return claims == 0
        ? LinkVerification.unavailable
        : LinkVerification.verified;
  }

  /// Shows the key entry gate.
  ///
  /// A key that came in the link but could not be decoded is reported as a
  /// damaged link rather than as a plain locked file: the recipient was sent a
  /// key and would otherwise be left wondering why it is being ignored. The
  /// gate is the same one either way, so a working key typed by hand still
  /// unlocks the file - and typing one is the only way out, since no key can be
  /// recovered from the network.
  void _emitLocked(SharedFileLinkPayload? payload) {
    emit(linkKeyIsDamaged
        ? SharedFileKeyInvalid(linkKeyIsDamaged: true, payload: payload)
        : SharedFileIsPrivate(payload: payload));
  }

  void _emitVerification(
    LinkVerification verification, {
    required int resolution,
  }) {
    if (_isStale(resolution)) {
      return;
    }

    final current = state;

    if (current is SharedFileLoadSuccess) {
      emit(current.copyWith(verification: verification));
    }
  }

  /// Whether a newer load has started, or the cubit is gone.
  bool _isStale(int resolution) => isClosed || resolution != _resolution;

  /// The link carries no timestamps. Rendered as "unknown", never as 1970.
  static final unknownDate = DateTime.fromMillisecondsSinceEpoch(0);

  /// Whether [date] is the placeholder a link-derived revision carries.
  ///
  /// A link carries no timestamps, so anything painted from one has this in
  /// place of a date. The UI asks rather than rendering it: shown, it reads as
  /// 1 January 1970, which is worse than showing nothing.
  static bool isUnknownDate(DateTime date) => date == unknownDate;
}

/// A revision resolved straight from its metadata transaction.
class _SharedRevision {
  /// The file the metadata describes, or `null` when it is encrypted and there
  /// is no key ([isLocked]).
  final FileEntity? entity;

  /// The address that posted the metadata transaction.
  final String? ownerAddress;

  /// Whether the metadata is encrypted and could not be opened without a key.
  final bool isLocked;

  const _SharedRevision({
    this.entity,
    this.ownerAddress,
    this.isLocked = false,
  });
}

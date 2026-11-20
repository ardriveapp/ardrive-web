import 'package:ardrive/core/crypto/file_keys.dart';
import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/data/drive_state_import.dart';
import 'package:ardrive/drive_state/domain/drive_state_protection.dart';
import 'package:ardrive/publication/data/publication_source.dart';
import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/publication/domain/publication_scope.dart';
import 'package:ardrive/publication/domain/publication_stats.dart';
import 'package:ardrive/publication/domain/sealed/seal_codec.dart';
import 'package:ardrive/publication/domain/sealed/sealing.dart';
import 'package:ardrive/pages/shared_file/shared_file_key_session.dart';
import 'package:ardrive/utils/shared_file_link.dart' show SharedFileLinkParams;
import 'package:ardrive/models/models.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/publication/data/publication_owner_lookup.dart';
import 'package:ardrive_utils/ardrive_utils.dart'
    show DrivePrivacyTag, EntityTag, EntityTypeTag;
import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'publication_loader_state.dart';

/// Opens a publication (docs/PUBLICATIONS.md, "How a page opens"):
///
/// 1. reads `publication.json` beside the page;
/// 2. a private drive or folder page (version 3) reads its sealed block and
///    opens it with the key in the link, the key this tab remembers, or what
///    the visitor types ([PublicationNeedsKey]); the block gives the files'
///    keys to [FileKeys] and names the catalog to import;
/// 3. seeds the drive's row, which the importer needs to import into;
/// 4. downloads the snapshot (or the catalog), reporting progress;
/// 5. imports it with the same `DriveStateImporter` a sync uses.
///
/// `publication.json` names its owner, and anyone can write one naming
/// anyone. So one GraphQL lookup on the serving gateway asks who really
/// signed the snapshot ([ownerOf]): someone else refuses the page. An answer
/// of nobody (a snapshot not indexed yet) opens it as declared: the byline
/// always shows the owner's address beside any display name.
///
/// No sync runs here or afterwards. The publication is exactly the snapshot.
class PublicationLoaderCubit extends Cubit<PublicationLoaderState> {
  PublicationLoaderCubit({
    required PublicationSource source,
    required String settingsPath,
    required DriveDao driveDao,
    required DriveStateImporter importer,
    required Future<String?> Function(String txId) ownerOf,
    Future<PublicationTxFacts?> Function(String txId)? factsOf,
    FileKeys? fileKeys,
    Sealing? sealing,
    SharedFileKeySession? keySession,
    String? linkKey,
  })  : _source = source,
        _factsOf = factsOf,
        _settingsPath = settingsPath,
        _driveDao = driveDao,
        _importer = importer,
        _ownerOf = ownerOf,
        _fileKeys = fileKeys ?? FileKeys(driveDao: driveDao),
        _sealing = sealing,
        _keySession = keySession ?? SharedFileKeySession.page(),
        _linkKey = linkKey,
        super(const PublicationLoadingSettings());

  final PublicationSource _source;
  final String _settingsPath;
  final DriveDao _driveDao;
  final DriveStateImporter _importer;

  /// Who signed a transaction, by the serving gateway; null when it does not
  /// know (`PublicationOwnerLookup.ownerOf`).
  final Future<String?> Function(String txId) _ownerOf;

  /// Who signed a transaction and its tags, for a file page's metadata; null
  /// falls back to [_ownerOf] alone.
  final Future<PublicationTxFacts?> Function(String txId)? _factsOf;

  /// Where a private page's file keys go, for preview and download to find.
  final FileKeys _fileKeys;

  /// Made on first use: a public page never needs it.
  Sealing? _sealing;
  Sealing get _seal => _sealing ??= Sealing();

  /// The publication key this tab remembers, by publication ID.
  final SharedFileKeySession _keySession;

  /// The `k` of the page's link: a private page's publication key.
  final String? _linkKey;

  PublicationConfig? _config;

  /// A private page's sealed block, read once.
  Uint8List? _sealedBytes;

  /// A private page, once open: what the sealed block said.
  OpenedPage? _opened;

  /// Whether this tab remembers the key the private page opened with.
  bool _remembered = false;

  /// Whether the page's settings were signed by the owner they name: null
  /// when that couldn't be checked.
  bool? _settingsSigned;

  /// Whether every part read so far is the transaction the settings name,
  /// as the gateway says. A page whose parts can't all be tied to the
  /// owner's transactions opens unverified.
  bool _partsBound = true;

  /// Whether the gateway served [txId] for [path]: true when it said so,
  /// false when it didn't say, or served another transaction of the same
  /// owner (settings and part from two versions of a page, as a cache or a
  /// name that just moved can give). Throws [_NotTheNamedPart] when it
  /// served a transaction someone else signed: a page built around the
  /// owner's real parts, where the owner check would prove nothing.
  Future<bool> _bound(
      PublicationConfig config, String path, String txId) async {
    final served = _source.dataIdOf(path);
    if (served == null) return false;
    if (served == txId) return true;
    if (await _signedBy(config, served) == false) {
      throw _NotTheNamedPart(path, txId, served);
    }
    return false;
  }

  Future<void> load() async {
    emit(const PublicationLoadingSettings());
    _settingsSigned = null;
    _partsBound = true;

    final PublicationConfig config;
    try {
      config =
          PublicationConfig.parse(await _source.readSettings(_settingsPath));
    } on PublicationConfigException catch (e) {
      logger.w('Publication settings refused: $e');
      emit(PublicationFailed(
        e.error == PublicationConfigError.unsupportedVersion
            ? PublicationFailure.needsNewerViewer
            : PublicationFailure.settingsUnreadable,
      ));
      return;
    } on PublicationSourceException catch (e) {
      logger.w('Publication settings unavailable: $e');
      emit(const PublicationFailed(PublicationFailure.settingsUnreadable));
      return;
    }
    _config = config;

    // The settings name the owner, the title and every part, so they must be
    // the owner's too: a page built by someone else around the owner's real
    // parts would otherwise pass as theirs. Bound to the transaction the
    // gateway says it served; without that, the page opens unverified.
    final settingsId = _source.dataIdOf(_settingsPath);
    _settingsSigned =
        settingsId == null ? null : await _signedBy(config, settingsId);
    if (_settingsSigned == false) {
      logger.w('Publication refused: its settings were signed by someone '
          'else than the owner they name');
      emit(_refused);
      return;
    }

    // A file page reads its one file from the network, as its share page
    // does; there is no snapshot to fetch and no drive to open. A private
    // one's key belongs to the file and is read by the share page from the
    // link, so the page does not wait for a drive key here.
    if (config.scope is PublicationFileScope) {
      await _openFilePage(config);
      return;
    }

    if (config.isSealed) {
      await _guard(config, () => _openPrivatePage(config));
      return;
    }

    // A private drive or folder page is version 3. The version 1 form, a
    // snapshot under the drive key, is reserved and never written, and
    // would need a key no visitor has.
    if (config.isPrivate) {
      logger.w('Publication refused: a private snapshot page');
      emit(const PublicationFailed(PublicationFailure.settingsUnreadable));
      return;
    }
    await _guard(config, () => _openSnapshotOrThrow(config));
  }

  /// Tries the snapshot or catalog again after
  /// [PublicationFailure.snapshotUnavailable].
  Future<void> retry() async {
    final config = _config;
    if (config == null) return load();
    if (config.scope is PublicationFileScope) return _openFilePage(config);
    if (config.isSealed) {
      final opened = _opened;
      return _guard(
        config,
        () => opened == null
            ? _openPrivatePage(config)
            : _openCatalog(config, opened),
      );
    }
    await _guard(config, () => _openSnapshotOrThrow(config));
  }

  /// Tries what the visitor typed on the unlock screen: the publication key,
  /// or the page's password. [input] is exactly what was typed: a key may
  /// come pasted with spaces around it, and a password may have them as
  /// part of it, so both are tried. With [remember], this tab keeps the key
  /// it opened with (never the password) until the tab closes.
  Future<void> unlock(String input, {required bool remember}) async {
    final config = _config;
    final sealedBytes = _sealedBytes;
    final state = this.state;
    if (config == null || sealedBytes == null) return;
    if (state is! PublicationNeedsKey || state.isChecking) return;
    if (input.isEmpty) return;

    emit(state.checking());
    final OpenedPage opened;
    try {
      opened = await _openWith(config, sealedBytes, input);
    } on SealError catch (e) {
      if (isClosed) return;
      if (e.code == SealErrorCode.noMatch) {
        emit(state.failed(PublicationUnlockError.didntOpen));
        return;
      }
      // A key opened a block that breaks the rules: the page is broken,
      // whatever the visitor types next.
      logger.w('Publication refused: its sealed block is invalid: $e');
      emit(_refused);
      return;
    } catch (e) {
      if (isClosed) return;
      // Argon2id itself failed (out of memory, the module did not load):
      // the password may have been right.
      logger.w('Publication password not checked: ${e.runtimeType}');
      emit(state.failed(PublicationUnlockError.passwordNotChecked));
      return;
    }
    if (isClosed) return;

    if (remember) {
      await _keySession.remember(
          config.sealed!.publicationId, b64u(opened.publicationKey));
      _remembered = true;
    }
    await _guard(config, () => _openCatalog(config, opened));
  }

  /// [input] as typed, then, when it differs only by spaces at either end
  /// from a key, that key. The key is tried first: it costs nothing, and a
  /// password is never key-shaped with spaces around it by accident.
  Future<OpenedPage> _openWith(
      PublicationConfig config, Uint8List sealedBytes, String input) async {
    final trimmed = input.trim();
    if (trimmed != input && keyFrom(trimmed) != null) {
      try {
        // As a key only: never spends a password check on it.
        return await _seal.openPage(
          config: config.sealed!.settings,
          sealedBytes: sealedBytes,
          linkKey: trimmed,
        );
      } on SealError catch (e) {
        if (e.code != SealErrorCode.noMatch) rethrow;
      }
    }
    return _seal.openPage(
      config: config.sealed!.settings,
      sealedBytes: sealedBytes,
      input: input,
    );
  }

  /// Stops remembering this page's key for this tab. The page stays open
  /// until it is reloaded.
  Future<void> forgetKey() async {
    final sealed = _config?.sealed;
    if (sealed == null) return;
    _remembered = false;
    await _keySession.forget(sealed.publicationId);
    final state = this.state;
    if (state is PublicationReady && state.keyRemembered) {
      emit(state.withKeyRemembered(false));
    }
  }

  /// Anything that goes wrong on the way that is not one of the named
  /// failures (the database not opening, `sqlite3.wasm` not loading, the
  /// importer throwing) ends on the retryable screen rather than on "Opening
  /// publication..." for ever: [load] runs unawaited, so an exception would
  /// otherwise leave the last state up.
  Future<void> _guard(
      PublicationConfig config, Future<void> Function() open) async {
    try {
      await open();
    } catch (e, stackTrace) {
      logger.e('Publication not opened', e, stackTrace);
      emit(PublicationFailed(PublicationFailure.snapshotUnavailable,
          config: config));
    }
  }

  /// A private drive or folder page (docs/ArweaveFS.md, "Opening a version 3
  /// page"): its sealed block, signed by its owner, opened with the link's
  /// key or the one this tab remembers; otherwise the unlock screen.
  Future<void> _openPrivatePage(PublicationConfig config) async {
    final sealed = config.sealed!;
    emit(PublicationLoadingSnapshot(config, received: 0, total: null));

    if (await _signedBy(config, sealed.txId) == false) {
      logger.w('Publication refused: its sealed block was signed by someone '
          'else than the owner it names');
      emit(_refused);
      return;
    }

    final Uint8List bytes;
    try {
      bytes = await _source.readPart(sealed.path, maxBytes: maxSealedBytes);
      _partsBound = await _bound(config, sealed.path, sealed.txId);
    } on _NotTheNamedPart catch (e) {
      logger.w('Publication refused: $e');
      emit(_refused);
      return;
    } on PublicationPartTooLarge catch (e) {
      logger.w('Publication refused: $e');
      emit(_refused);
      return;
    } on PublicationSourceException catch (e) {
      logger.w('Publication sealed block unavailable: $e');
      emit(PublicationFailed(PublicationFailure.snapshotUnavailable,
          config: config));
      return;
    }
    _sealedBytes = bytes;

    final page = readPrivatePublication(sealed.settings);
    final hasPassword = page.passwordSlot != null;

    // A key: the link's, then this tab's. Neither is ever tried as a
    // password, so a stale one costs nothing.
    final remembered = await _keySession.read(sealed.publicationId);
    for (final (key, isRemembered) in [
      (_linkKey, false),
      (remembered, true),
    ]) {
      if (key == null) continue;
      final OpenedPage opened;
      try {
        opened = await _seal.openPage(
          config: sealed.settings,
          sealedBytes: bytes,
          linkKey: key,
        );
      } on SealError catch (e) {
        if (e.code == SealErrorCode.noMatch) {
          // A remembered key that no longer opens the page would only ever
          // fail again.
          if (isRemembered) await _keySession.forget(sealed.publicationId);
          continue;
        }
        logger.w('Publication refused: its sealed block is invalid: $e');
        emit(_refused);
        return;
      }
      _remembered = isRemembered;
      await _openCatalog(config, opened);
      return;
    }

    emit(PublicationNeedsKey(
      config,
      hasPassword: hasPassword,
      error: _linkKey != null ? PublicationUnlockError.linkKeyDidntOpen : null,
    ));
  }

  /// A private page once its sealed block has opened: its files' keys go to
  /// [FileKeys], then its catalog is checked and imported like a snapshot,
  /// under the catalog's own key.
  Future<void> _openCatalog(PublicationConfig locked, OpenedPage opened) async {
    _opened = opened;
    final block = opened.block;
    final config = locked.opened(rootFolderId: block.rootFolderId);
    _config = config;
    _fileKeys.usePageKeys(config.driveId, block.files);

    final catalog = block.catalog;
    await _import(
      config,
      txId: catalog.txId,
      path: catalog.path,
      // The page names its drive; the block's tags may not name another.
      tags: {...catalog.tags, EntityTag.driveId: config.driveId},
      protection: DriveStateProtection.forCatalog(SecretKey(catalog.key)),
    );
  }

  /// Opens a file page once its byline is checked: the file's metadata must
  /// have been signed by the owner the page names, the same rule a drive or
  /// folder page applies to its snapshot, and must be its file's: anyone's
  /// real metadata for some other file proves nothing about this one. Only a
  /// confirmed mismatch refuses.
  Future<void> _openFilePage(PublicationConfig config) async {
    final metadataTxId = config.file!.metadataTxId;
    final bool? ownerMatches;
    final factsOf = _factsOf;
    if (factsOf == null) {
      ownerMatches = await _signedBy(config, metadataTxId);
    } else {
      PublicationTxFacts? facts;
      try {
        facts = await factsOf(metadataTxId);
      } catch (e) {
        logger.w('Publication owner not checked: $e');
      }
      final fileId = (config.scope as PublicationFileScope).fileId;
      ownerMatches = facts == null
          ? null
          : facts.owner == config.owner &&
              facts.tags[EntityTag.entityType] == EntityTypeTag.file &&
              facts.tags[EntityTag.fileId] == fileId &&
              facts.tags[EntityTag.driveId] == config.driveId;
    }
    if (ownerMatches == false) {
      logger.w('Publication refused: its file was signed by someone else '
          'than the owner it names, or is not the file it names');
      emit(_refused);
      return;
    }
    PublicationContents.open = null;
    emit(PublicationReady(config,
        ownerVerified: _settingsSigned == true && ownerMatches == true));
  }

  /// A page refused for what it holds shows nothing it says about itself:
  /// no title, no icon, no display name. Its settings are not trusted.
  static const _refused =
      PublicationFailed(PublicationFailure.snapshotRejected);

  /// Whether [txId]'s real signer is [config]'s owner: true, false, or null
  /// when the gateway cannot say.
  Future<bool?> _signedBy(PublicationConfig config, String txId) async {
    final String? signer;
    try {
      signer = await _ownerOf(txId);
    } catch (e) {
      logger.w('Publication owner not checked: $e');
      return null;
    }
    if (signer == null) return null;
    return signer == config.owner;
  }

  Future<void> _openSnapshotOrThrow(PublicationConfig config) async {
    final snapshot = config.snapshot!;
    await _import(
      config,
      txId: snapshot.txId,
      path: snapshot.path,
      tags: snapshot.tags,
      protection: DriveStateProtection.forDrive(
        privacy: config.privacy,
        driveKey: null,
      ).protection,
    );
  }

  /// Imports a page's drive state: a public page's snapshot, or a private
  /// page's catalog. [protection] is null when the page's privacy has none.
  Future<void> _import(
    PublicationConfig config, {
    required String txId,
    required String path,
    required Map<String, String> tags,
    required DriveStateProtection? protection,
  }) async {
    final ownerMatches = await _signedBy(config, txId);
    if (ownerMatches == false) {
      logger.w('Publication refused: its drive state was signed by someone '
          'else than the owner it names');
      emit(_refused);
      return;
    }
    // Only a confirmed mismatch refuses. No answer (a new snapshot is not
    // indexed until its bundle is mined) opens the page as declared, with
    // the address the byline always shows beside any display name.
    final signed = _settingsSigned == true && ownerMatches == true;

    await _driveDao.writePublicationDrive(
      driveId: config.driveId,
      rootFolderId: config.rootFolderId,
      ownerAddress: config.owner,
      privacy: config.privacy,
      // A private drive's name is a secret the snapshot holds; the title is
      // what the owner chose to show.
      name: config.privacy == DrivePrivacyTag.public ? config.title : '',
    );

    emit(PublicationLoadingSnapshot(config, received: 0, total: null));
    final Uint8List body;
    try {
      body = await _source.readSnapshot(
        path,
        maxBytes: maxSnapshotBytes,
        onProgress: (received, total) => emit(
          PublicationLoadingSnapshot(config, received: received, total: total),
        ),
      );
      if (!await _bound(config, path, txId)) _partsBound = false;
    } on _NotTheNamedPart catch (e) {
      logger.w('Publication refused: $e');
      emit(_refused);
      return;
    } on PublicationPartTooLarge catch (e) {
      logger.w('Publication refused: $e');
      emit(_refused);
      return;
    } on PublicationSourceException catch (e) {
      logger.w('Publication snapshot unavailable: $e');
      emit(PublicationFailed(PublicationFailure.snapshotUnavailable,
          config: config));
      return;
    }

    emit(PublicationImporting(config));
    if (protection == null) {
      logger.w('Publication snapshot not opened: no protection for '
          '${config.privacy}');
      emit(_refused);
      return;
    }

    final result = await _importer.import(
      candidate: DriveStateArtifactCandidate(
        txId: txId,
        ownerAddress: config.owner,
        tags: tags,
      ),
      body: body,
      protection: protection,
      expectedOwnerAddress: config.owner,
    );
    if (!result.isImported) {
      logger.w('Publication snapshot rejected: $result');
      emit(_refused);
      return;
    }

    // A folder publication whose folder the snapshot does not hold would open on
    // nothing, or on the drive's root, which the owner did not publish.
    if (config.scope case PublicationFolderScope(:final folderId)) {
      final folder =
          await _driveDao.folderById(folderId: folderId).getSingleOrNull();
      if (folder == null || folder.driveId != config.driveId) {
        logger.w('Publication snapshot has no folder $folderId');
        emit(_refused);
        return;
      }
    }

    logger.i('Publication imported: ${result.detail}');
    // What the publication shows, read once: downloads and the info panel prune
    // the drive's folder trees with it (see [PublicationContents.open]).
    final contents = await PublicationContents.load(_driveDao, config);
    PublicationContents.open = contents;
    emit(PublicationReady(
      config,
      stats: PublicationStats.of(contents),
      // For a private page, the catalog's signer: its sealed block was
      // checked too, and refused only on a confirmed mismatch.
      ownerVerified: signed && _partsBound,
      keyRemembered: _remembered,
    ));
  }
}

/// The `k` of a page's link (`<page>#/?k=<key>`, or in any folder route of
/// the page): a private drive or folder page's publication key. Null when
/// the link has none. Its shape is not checked here: a malformed one is
/// passed over when the page opens, not an error.
String? publicationLinkKey(Uri page) {
  final route = Uri.tryParse(page.fragment);
  final key = route?.queryParameters[SharedFileLinkParams.key];
  return key == null || key.isEmpty ? null : key;
}

/// A page part the gateway served from another transaction than the page's
/// settings name, signed by someone other than their owner.
class _NotTheNamedPart implements Exception {
  const _NotTheNamedPart(this.path, this.named, this.served);

  final String path;
  final String named;
  final String served;

  @override
  String toString() => '$path is $served, not $named as the settings name';
}

/// The largest snapshot or catalog a page may have: what the importer
/// accepts uncompressed (`DriveStateEnvelope.defaultMaxPlaintextBytes`),
/// with room for gzip's and the cipher's overhead.
const maxSnapshotBytes = 104 * 1024 * 1024;

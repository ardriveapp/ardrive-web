import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/data/drive_state_import.dart';
import 'package:ardrive/drive_state/domain/drive_state_protection.dart';
import 'package:ardrive/library/data/library_source.dart';
import 'package:ardrive/library/domain/library_config.dart';
import 'package:ardrive/library/domain/library_scope.dart';
import 'package:ardrive/library/domain/library_stats.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart' show DrivePrivacyTag;
import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'library_loader_state.dart';

/// Opens a library page (docs/LIBRARY_PAGES.md, "How a page opens"):
///
/// 1. reads `library.json` beside the page;
/// 2. a private library waits for its key ([LibraryNeedsKey]);
/// 3. seeds the drive's row, which the importer needs to import into;
/// 4. downloads the snapshot, reporting progress;
/// 5. imports it with the same `DriveStateImporter` a sync uses.
///
/// The importer checks the snapshot was uploaded by the owner `library.json`
/// names, which is as trustworthy as the page itself, and nothing more is
/// asked of anyone: there is no GraphQL owner lookup on a library page.
///
/// No sync runs here or afterwards. The library is exactly the snapshot.
class LibraryLoaderCubit extends Cubit<LibraryLoaderState> {
  LibraryLoaderCubit({
    required LibrarySource source,
    required String settingsPath,
    required DriveDao driveDao,
    required DriveStateImporter importer,
  })  : _source = source,
        _settingsPath = settingsPath,
        _driveDao = driveDao,
        _importer = importer,
        super(const LibraryLoadingSettings());

  final LibrarySource _source;
  final String _settingsPath;
  final DriveDao _driveDao;
  final DriveStateImporter _importer;

  LibraryConfig? _config;
  SecretKey? _driveKey;

  Future<void> load() async {
    emit(const LibraryLoadingSettings());

    final LibraryConfig config;
    try {
      config = LibraryConfig.parse(await _source.readSettings(_settingsPath));
    } on LibraryConfigException catch (e) {
      logger.w('Library settings refused: $e');
      emit(LibraryFailed(
        e.error == LibraryConfigError.unsupportedVersion
            ? LibraryFailure.needsNewerViewer
            : LibraryFailure.settingsUnreadable,
      ));
      return;
    } on LibrarySourceException catch (e) {
      logger.w('Library settings unavailable: $e');
      emit(const LibraryFailed(LibraryFailure.settingsUnreadable));
      return;
    }
    _config = config;

    if (config.isPrivate && _driveKey == null) {
      emit(LibraryNeedsKey(config));
      return;
    }
    await _openSnapshot(config);
  }

  /// Tries the snapshot again after [LibraryFailure.snapshotUnavailable].
  Future<void> retry() async {
    final config = _config;
    if (config == null) return load();
    await _openSnapshot(config);
  }

  /// Anything that goes wrong on the way that is not one of the named
  /// failures (the database not opening, `sqlite3.wasm` not loading, the
  /// importer throwing) ends on the retryable screen rather than on "Opening
  /// library..." for ever: [load] runs unawaited, so an exception would
  /// otherwise leave the last state up.
  Future<void> _openSnapshot(LibraryConfig config) async {
    try {
      await _openSnapshotOrThrow(config);
    } catch (e, stackTrace) {
      logger.e('Library not opened', e, stackTrace);
      emit(LibraryFailed(LibraryFailure.snapshotUnavailable, config: config));
    }
  }

  Future<void> _openSnapshotOrThrow(LibraryConfig config) async {
    await _driveDao.writeLibraryDrive(
      driveId: config.driveId,
      rootFolderId: config.rootFolderId,
      ownerAddress: config.owner,
      privacy: config.privacy,
      // A private drive's name is a secret the snapshot holds; the title is
      // what the owner chose to show.
      name: config.privacy == DrivePrivacyTag.public ? config.title : '',
    );

    emit(LibraryLoadingSnapshot(config, received: 0, total: null));
    final Uint8List body;
    try {
      body = await _source.readSnapshot(
        config.snapshot.path,
        onProgress: (received, total) => emit(
          LibraryLoadingSnapshot(config, received: received, total: total),
        ),
      );
    } on LibrarySourceException catch (e) {
      logger.w('Library snapshot unavailable: $e');
      emit(LibraryFailed(LibraryFailure.snapshotUnavailable, config: config));
      return;
    }

    emit(LibraryImporting(config));
    final protection = DriveStateProtection.forDrive(
      privacy: config.privacy,
      driveKey: _driveKey,
    );
    final resolved = protection.protection;
    if (resolved == null) {
      logger.w('Library snapshot not opened: ${protection.refusal}');
      emit(LibraryFailed(LibraryFailure.snapshotRejected, config: config));
      return;
    }

    final result = await _importer.import(
      candidate: DriveStateArtifactCandidate(
        txId: config.snapshot.txId,
        ownerAddress: config.owner,
        tags: config.snapshot.tags,
      ),
      body: body,
      protection: resolved,
      expectedOwnerAddress: config.owner,
    );
    if (!result.isImported) {
      logger.w('Library snapshot rejected: $result');
      emit(LibraryFailed(LibraryFailure.snapshotRejected, config: config));
      return;
    }

    // A folder library whose folder the snapshot does not hold would open on
    // nothing, or on the drive's root, which the owner did not publish.
    if (config.scope case LibraryFolderScope(:final folderId)) {
      final folder =
          await _driveDao.folderById(folderId: folderId).getSingleOrNull();
      if (folder == null || folder.driveId != config.driveId) {
        logger.w('Library snapshot has no folder $folderId');
        emit(LibraryFailed(LibraryFailure.snapshotRejected, config: config));
        return;
      }
    }

    logger.i('Library imported: ${result.detail}');
    // What the library shows, read once: downloads and the info panel prune
    // the drive's folder trees with it (see [LibraryContents.open]).
    final contents = await LibraryContents.load(_driveDao, config);
    LibraryContents.open = contents;
    emit(LibraryReady(config, stats: LibraryStats.of(contents)));
  }
}

import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/data/drive_state_import.dart';
import 'package:ardrive/drive_state/domain/drive_state_protection.dart';
import 'package:ardrive/publication/data/publication_source.dart';
import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/publication/domain/publication_scope.dart';
import 'package:ardrive/publication/domain/publication_stats.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart' show DrivePrivacyTag;
import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'publication_loader_state.dart';

/// Opens a publication (docs/PUBLICATIONS.md, "How a page opens"):
///
/// 1. reads `publication.json` beside the page;
/// 2. a private publication waits for its key ([PublicationNeedsKey]);
/// 3. seeds the drive's row, which the importer needs to import into;
/// 4. downloads the snapshot, reporting progress;
/// 5. imports it with the same `DriveStateImporter` a sync uses.
///
/// The importer checks the snapshot was uploaded by the owner `publication.json`
/// names, which is as trustworthy as the page itself, and nothing more is
/// asked of anyone: there is no GraphQL owner lookup on a publication.
///
/// No sync runs here or afterwards. The publication is exactly the snapshot.
class PublicationLoaderCubit extends Cubit<PublicationLoaderState> {
  PublicationLoaderCubit({
    required PublicationSource source,
    required String settingsPath,
    required DriveDao driveDao,
    required DriveStateImporter importer,
  })  : _source = source,
        _settingsPath = settingsPath,
        _driveDao = driveDao,
        _importer = importer,
        super(const PublicationLoadingSettings());

  final PublicationSource _source;
  final String _settingsPath;
  final DriveDao _driveDao;
  final DriveStateImporter _importer;

  PublicationConfig? _config;
  SecretKey? _driveKey;

  Future<void> load() async {
    emit(const PublicationLoadingSettings());

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

    if (config.isPrivate && _driveKey == null) {
      emit(PublicationNeedsKey(config));
      return;
    }
    await _openSnapshot(config);
  }

  /// Tries the snapshot again after [PublicationFailure.snapshotUnavailable].
  Future<void> retry() async {
    final config = _config;
    if (config == null) return load();
    await _openSnapshot(config);
  }

  /// Anything that goes wrong on the way that is not one of the named
  /// failures (the database not opening, `sqlite3.wasm` not loading, the
  /// importer throwing) ends on the retryable screen rather than on "Opening
  /// publication..." for ever: [load] runs unawaited, so an exception would
  /// otherwise leave the last state up.
  Future<void> _openSnapshot(PublicationConfig config) async {
    try {
      await _openSnapshotOrThrow(config);
    } catch (e, stackTrace) {
      logger.e('Publication not opened', e, stackTrace);
      emit(PublicationFailed(PublicationFailure.snapshotUnavailable,
          config: config));
    }
  }

  Future<void> _openSnapshotOrThrow(PublicationConfig config) async {
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
        config.snapshot.path,
        onProgress: (received, total) => emit(
          PublicationLoadingSnapshot(config, received: received, total: total),
        ),
      );
    } on PublicationSourceException catch (e) {
      logger.w('Publication snapshot unavailable: $e');
      emit(PublicationFailed(PublicationFailure.snapshotUnavailable,
          config: config));
      return;
    }

    emit(PublicationImporting(config));
    final protection = DriveStateProtection.forDrive(
      privacy: config.privacy,
      driveKey: _driveKey,
    );
    final resolved = protection.protection;
    if (resolved == null) {
      logger.w('Publication snapshot not opened: ${protection.refusal}');
      emit(PublicationFailed(PublicationFailure.snapshotRejected,
          config: config));
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
      logger.w('Publication snapshot rejected: $result');
      emit(PublicationFailed(PublicationFailure.snapshotRejected,
          config: config));
      return;
    }

    // A folder publication whose folder the snapshot does not hold would open on
    // nothing, or on the drive's root, which the owner did not publish.
    if (config.scope case PublicationFolderScope(:final folderId)) {
      final folder =
          await _driveDao.folderById(folderId: folderId).getSingleOrNull();
      if (folder == null || folder.driveId != config.driveId) {
        logger.w('Publication snapshot has no folder $folderId');
        emit(PublicationFailed(PublicationFailure.snapshotRejected,
            config: config));
        return;
      }
    }

    logger.i('Publication imported: ${result.detail}');
    // What the publication shows, read once: downloads and the info panel prune
    // the drive's folder trees with it (see [PublicationContents.open]).
    final contents = await PublicationContents.load(_driveDao, config);
    PublicationContents.open = contents;
    emit(PublicationReady(config, stats: PublicationStats.of(contents)));
  }
}

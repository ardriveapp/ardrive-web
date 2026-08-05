import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/license_assertion.dart';
import 'package:ardrive/entities/license_composed.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'shared_file_state.dart';

/// [SharedFileCubit] includes logic for displaying a file shared with another user.
class SharedFileCubit extends Cubit<SharedFileState> {
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

  /// The [SecretKey] the last load was attempted with.
  ///
  /// Starts as [fileKey] and is replaced by any key the user submits, so that
  /// [retry] runs with the key that was last used.
  SecretKey? _lastAttemptedFileKey;

  SharedFileCubit({
    required this.fileId,
    this.fileKey,
    this.linkKeyIsDamaged = false,
    required arweave,
    required licenseService,
  })  : _arweave = arweave,
        _licenseService = licenseService,
        super(SharedFileLoadInProgress()) {
    loadFileDetails(fileKey);
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

  Future<void> loadFileDetails(SecretKey? fileKey) async {
    _lastAttemptedFileKey = fileKey;

    try {
      emit(SharedFileLoadInProgress());
      final privacy = await _arweave.getFilePrivacyForId(fileId);
      if (fileKey == null && privacy == DrivePrivacyTag.private) {
        // A key that came in the link but could not be decoded is reported as a
        // damaged link rather than as a plain locked file: the recipient was
        // sent a key and would otherwise be left wondering why it is being
        // ignored. The key entry gate is the same one either way, so a working
        // key typed by hand still unlocks the file.
        emit(linkKeyIsDamaged
            ? const SharedFileKeyInvalid(linkKeyIsDamaged: true)
            : SharedFileIsPrivate());
        return;
      }
      final allEntities = await _arweave.getAllFileEntitiesWithId(
        fileId,
        fileKey,
      );
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
        // revisions are in reverse chronological order, so first is most recent
        final latestLicense = revisions.first.licenseTxId != null
            ? await fetchLicenseForRevision(
                revisions.first,
                owner: ownerAddress,
              )
            : null;

        emit(SharedFileLoadSuccess(
          fileRevisions: revisions,
          fileKey: fileKey,
          latestLicense: latestLicense,
          ownerAddress: ownerAddress,
        ));
        return;
      }

      // No revision could be read. When the privacy probe resolved the file as
      // private and a key was supplied, it is the key that is wrong and not the
      // file that is missing: every revision failed to decrypt and was skipped.
      if (fileKey != null && privacy == DrivePrivacyTag.private) {
        emit(const SharedFileKeyInvalid());
        return;
      }

      emit(SharedFileNotFound());
    } catch (e, stacktrace) {
      logger.e('Failed to load the details of the shared file', e, stacktrace);
      emit(SharedFileLoadFailure());
    }
  }

  /// Runs the load again with the key that was last attempted.
  Future<void> retry() => loadFileDetails(_lastAttemptedFileKey);

  Future<void> launchPreview(TxID dataTxId) =>
      openUrl(url: '${_arweave.client.api.gatewayUrl}/$dataTxId');

  Future<void> submit(String fileKeyBase64) async {
    emit(SharedFileLoadInProgress());

    final SecretKey fileKey;

    try {
      fileKey = SecretKey(decodeBase64ToBytes(fileKeyBase64));
    } catch (e) {
      logger.e('Failed to decode the submitted file key', e);
      emit(const SharedFileKeyInvalid());
      return;
    }

    _lastAttemptedFileKey = fileKey;

    try {
      final file = await _arweave.getLatestFileEntityWithId(fileId, fileKey);

      if (file == null) {
        // The file exists - it is what the user is looking at - so the key is
        // what could not decrypt its metadata.
        emit(const SharedFileKeyInvalid());
        return;
      }
    } catch (e, stacktrace) {
      logger.e('Failed to submit file key', e, stacktrace);
      emit(SharedFileLoadFailure());
      return;
    }

    await loadFileDetails(fileKey);
  }
}

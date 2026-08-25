import 'dart:async';
import 'dart:convert';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/link_generators.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/shared_file_link.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'file_share_state.dart';

/// [FileShareCubit] includes logic for the user to retrieve a link to share a public/private file with.
///
/// The link it builds is the v2 schema of `docs/FILE_SHARING_REDESIGN_PLAN.md`
/// §1.2. Every field but `c`/`iv` comes from the local database, so the link is
/// ready before any network call returns; `c`/`iv` are fetched in the
/// background and folded in when they land (see [_loadCipherDetails]).
class FileShareCubit extends Cubit<FileShareState> {
  final String driveId;
  final String fileId;

  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;
  final ArweaveService _arweave;

  FileShareCubit({
    required this.driveId,
    required this.fileId,
    required ProfileCubit profileCubit,
    required DriveDao driveDao,
    required ArweaveService arweave,
  })  : _profileCubit = profileCubit,
        _driveDao = driveDao,
        _arweave = arweave,
        super(FileShareLoadInProgress()) {
    loadFileShareDetails();
  }

  // Everything the link is rebuilt from. Toggling an option must never cost a
  // database read or a network call - the sharer is standing in front of a
  // dialog with a link in it.
  String? _fileName;
  bool _isPublicFile = true;
  bool _isPending = false;
  String? _fileKeyBase64;

  String? _dataTxId;
  String? _metadataTxId;
  String? _ownerAddress;
  String? _name;
  int? _size;
  String? _contentType;
  String? _bundledInTxId;
  String? _thumbnailTxId;

  String? _cipher;
  String? _cipherIv;
  bool _isLoadingCipherDetails = false;

  bool _detailsAreHidden = false;
  bool _isPinned = false;
  bool _keyIsInLink = false;

  Future<void> loadFileShareDetails() async {
    emit(FileShareLoadInProgress());

    final drive = await _driveDao.driveById(driveId: driveId).getSingle();

    final file = await _driveDao.fileById(fileId: fileId).getSingle();

    final dataTxStatus = (await (_driveDao.select(_driveDao.networkTransactions)
              ..where((entry) => entry.id.equals(file.dataTxId)))
            .getSingle())
        .status;

    if (dataTxStatus == TransactionStatus.failed) {
      emit(FileShareLoadedFailedFile());
      return;
    }

    // `mtx` lives only on the revision - `file_entries` has no metadata
    // transaction id - and so do the revision's own `in`/`thn`. A revision
    // that points at a different data transaction than the file entry is a
    // revision for a different set of bytes, so it is not used to describe
    // this link.
    final latestRevision = await _driveDao
        .latestFileRevisionByFileId(driveId: driveId, fileId: fileId)
        .getSingleOrNull();
    final sharedRevision =
        latestRevision?.dataTxId == file.dataTxId ? latestRevision : null;

    SecretKey? fileKey;

    if (drive.privacy == DrivePrivacyTag.private) {
      final profile = _profileCubit.state;
      DriveKey? driveKey;

      if (profile is ProfileLoggedIn) {
        driveKey = await _driveDao.getDriveKey(
          drive.id,
          profile.user.cipherKey,
        );
      } else {
        driveKey = await _driveDao.getDriveKeyFromMemory(driveId);
      }

      if (driveKey == null) {
        throw StateError('Drive Key not found');
      }

      fileKey = await _driveDao.getFileKey(fileId, driveKey.key);
    }

    _fileName = file.name;
    _isPublicFile = drive.isPublic;
    _isPending = dataTxStatus == TransactionStatus.pending;
    _fileKeyBase64 = fileKey == null
        ? null
        : encodeBytesToBase64(await fileKey.extractBytes());

    _dataTxId = file.dataTxId;
    _metadataTxId = sharedRevision?.metadataTxId;
    _ownerAddress = drive.ownerAddress;
    _name = file.name;
    _size = file.size;
    _contentType = file.dataContentType;
    _bundledInTxId = sharedRevision?.bundledIn ?? file.bundledIn;
    _thumbnailTxId =
        _thumbnailTxIdOf(sharedRevision?.thumbnail ?? file.thumbnail);

    // A pinned file's data transaction belongs to somebody else and is not
    // encrypted, so it carries no cipher tags to fetch - the same test the
    // download path makes (`shared_file_download_cubit.dart`).
    final needsCipherDetails =
        fileKey != null && file.pinnedDataOwnerAddress == null;

    _isLoadingCipherDetails = needsCipherDetails;

    _emitLoadSuccess();

    if (needsCipherDetails) {
      unawaited(_loadCipherDetails(file.dataTxId));
    }
  }

  /// Leaves the file's name, size and content type out of the link, and marks
  /// it `hid` so the recipient's locked page can say why it knows nothing.
  void setDetailsAreHidden(bool value) {
    if (_detailsAreHidden == value || state is! FileShareLoadSuccess) {
      return;
    }

    _detailsAreHidden = value;
    _emitLoadSuccess();
  }

  /// Pins the link to the revision it was built from (decision 1). Off by
  /// default: a link that follows the file is what a sharer usually means.
  void setPinnedToCurrentVersion(bool value) {
    if (_isPinned == value || state is! FileShareLoadSuccess) {
      return;
    }

    _isPinned = value;
    _emitLoadSuccess();
  }

  /// Embeds the file key in the link, collapsing the two-artifact handover
  /// into one artifact that opens the file on its own (decision 4).
  void setKeyIsInLink(bool value) {
    if (_keyIsInLink == value || state is! FileShareLoadSuccess) {
      return;
    }

    _keyIsInLink = value;
    _emitLoadSuccess();
  }

  /// How long the one network read on this side may take before the link is
  /// presented as final without `c`/`iv`.
  static const _cipherDetailsTimeout = Duration(seconds: 10);

  /// Fetches `c`/`iv` - the only two link fields that are not in the local
  /// database - and folds them into the link when they arrive.
  ///
  /// A failure here is not a failed share: without `c`/`iv` the recipient pays
  /// one `getTransactionDetails` at download time, which is exactly what every
  /// link built before this schema does today (§1.2).
  Future<void> _loadCipherDetails(String dataTxId) async {
    try {
      // Bounded. `GraphQLRetry` retries a call that throws but sets no
      // timeout, so a gateway that simply hangs would leave the dialog saying
      // "finishing your link" for as long as it stayed open - telling the
      // sharer to wait for something that is already done. The link is
      // complete and copyable without `c`/`iv`; those two fields only save the
      // recipient one lookup.
      final dataTx = await _arweave
          .getTransactionDetails(dataTxId)
          .timeout(_cipherDetailsTimeout);

      if (isClosed) {
        return;
      }

      _cipher = dataTx?.getTag(EntityTag.cipher);
      _cipherIv = dataTx?.getTag(EntityTag.cipherIv);

      if (_cipher == null || _cipherIv == null) {
        logger.w(
          'The data transaction of a shared private file carries no cipher '
          'tags. The link will omit `c`/`iv`.',
        );
      }
    } catch (e) {
      logger.e('Failed to fetch the cipher details of a shared file link', e);
    } finally {
      _isLoadingCipherDetails = false;

      if (!isClosed && state is FileShareLoadSuccess) {
        _emitLoadSuccess();
      }
    }
  }

  void _emitLoadSuccess() {
    emit(
      FileShareLoadSuccess(
        fileName: _fileName ?? '',
        fileShareLink: _buildLink(),
        isPublicFile: _isPublicFile,
        isPending: _isPending,
        fileKeyBase64: _fileKeyBase64,
        keyIsInLink: _keyIsInLink,
        detailsAreHidden: _detailsAreHidden,
        isPinned: _isPinned,
        isLoadingCipherDetails: _isLoadingCipherDetails,
      ),
    );
  }

  Uri _buildLink() => generateFileShareLinkV2(
        fileId: fileId,
        payload: SharedFileLinkPayload(
          dataTxId: _dataTxId,
          metadataTxId: _metadataTxId,
          ownerAddress: _ownerAddress,
          name: _detailsAreHidden ? null : _name,
          size: _detailsAreHidden ? null : _size,
          contentType: _detailsAreHidden ? null : _contentType,
          cipher: _cipher,
          cipherIv: _cipherIv,
          isPinned: _isPinned,
          bundledInTxId: _bundledInTxId,
          thumbnailTxId: _thumbnailTxId,
          detailsAreHidden: _detailsAreHidden,
        ),
        rawFileKey: _keyIsInLink ? _fileKeyBase64 : null,
      );
}

/// Reads the thumbnail transaction id out of the thumbnail column, which holds
/// the `{"variants": [...]}` JSON of the file's metadata rather than a bare
/// transaction id.
String? _thumbnailTxIdOf(String? thumbnail) {
  if (thumbnail == null || thumbnail.isEmpty || thumbnail == 'null') {
    return null;
  }

  try {
    final decoded = jsonDecode(thumbnail);

    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    final variants = decoded['variants'];

    if (variants is! List || variants.isEmpty) {
      return null;
    }

    final variant = variants.first;
    final txId = variant is Map<String, dynamic> ? variant['txId'] : null;

    return txId is String && txId.isNotEmpty ? txId : null;
  } catch (e) {
    // A thumbnail is a nicety; a malformed one never costs the sharer a link.
    logger.w('Could not read the thumbnail id of a shared file: $e');

    return null;
  }
}

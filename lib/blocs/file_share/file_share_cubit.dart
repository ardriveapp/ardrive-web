import 'dart:async';
import 'dart:convert';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/link_generators.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/shared_file_link.dart';
// Aliased: `cryptography` exports a `Cipher` of its own, and this file needs
// both packages.
import 'package:ardrive_crypto/ardrive_crypto.dart' as ardrive_crypto;
import 'package:ardrive_uploader/ardrive_uploader.dart'
    show maxSizeSupportedByGCMEncryption;
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

  /// Whether a private file's cipher could not be resolved.
  ///
  /// `c` is not an optimization. It is the only thing that tells a recipient
  /// holding no key that the file is encrypted: without it the page reads the
  /// file as public, and a download writes ciphertext to disk under the file's
  /// own name. A link missing it is not a slower link, it is a broken one, so
  /// the sharer is told rather than handed it silently.
  bool _cipherDetailsFailed = false;
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
  ///
  /// Raised from ten seconds, which was under `GraphQLRetry`'s own ladder: it
  /// sleeps about six seconds across its five attempts on the primary endpoint
  /// before falling back to Goldsky, so a ten second budget expired part way
  /// through the primary and the fallback never ran. That is the difference
  /// between a link that carries `c`/`iv` and one that only declares the file
  /// encrypted, on exactly the connection where it matters most.
  static const _cipherDetailsTimeout = Duration(seconds: 15);

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
        _cipherDetailsFailed = true;

        logger.w(
          'The data transaction of a shared private file carries no cipher '
          'tags. The link will declare the file encrypted without them.',
        );
      }
    } catch (e) {
      _cipherDetailsFailed = true;

      logger.e('Failed to fetch the cipher details of a shared file link', e);
    } finally {
      _declarePrivacyWithoutTheGateway();
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
        cipherDetailsFailed: _cipherDetailsFailed,
      ),
    );
  }

  /// Asks again for the cipher a private link needs.
  ///
  /// Cheap to offer: [ArweaveService.getTransactionDetails] memoizes by id, so
  /// a lookup that has since succeeded for this transaction answers without
  /// touching the network at all.
  Future<void> retryCipherDetails() async {
    final dataTxId = _dataTxId;

    if (_isLoadingCipherDetails || dataTxId == null) {
      return;
    }

    _cipherDetailsFailed = false;
    _isLoadingCipherDetails = true;
    _emitLoadSuccess();

    await _loadCipherDetails(dataTxId);
  }

  /// Makes the link say "this file is encrypted" even when the gateway would
  /// not say what it is encrypted *with*.
  ///
  /// `c` does two unrelated jobs. With `iv` beside it, it tells the recipient
  /// which algorithm to decrypt with. On its own it does something far more
  /// basic: it is the only thing that tells a recipient holding no key that a
  /// key is needed at all. Without it the page reads a private file as public,
  /// never prompts for the key, and offers a download that cannot work.
  ///
  /// The IV is random per upload and is only on the transaction, so it cannot
  /// be recovered locally - nothing in the local database keeps it. The
  /// algorithm can be inferred: this uploader writes AES-GCM below
  /// [maxSizeSupportedByGCMEncryption] and AES-CTR above it.
  ///
  /// That inference can be wrong - `ardrive-cli` wrote AES-GCM at any size -
  /// and it does not matter, because a `c` set here is never decrypted with.
  /// Every consumer that decrypts requires `hasCipherDetails`, which is `c`
  /// *and* `iv`, and this only runs when `c` could not be fetched. What it
  /// buys is the locked state, which is right regardless of algorithm.
  void _declarePrivacyWithoutTheGateway() {
    // Only `c` decides this. Testing `iv` as well would let the one case where
    // the gateway returned an IV and no cipher skip the inference and ship a
    // link with `iv` and no `c` - which is precisely the link this exists to
    // prevent, because the recipient's locked state keys off `c` alone.
    if (_cipher != null) {
      return;
    }

    if (_fileKeyBase64 == null) {
      return;
    }

    // An IV with no cipher beside it decrypts nothing and would only travel as
    // dead weight; `hasCipherDetails` requires both.
    _cipherIv = null;

    _cipher = (_size ?? 0) <= maxSizeSupportedByGCMEncryption
        ? ardrive_crypto.Cipher.aes256gcm
        : ardrive_crypto.Cipher.aes256ctr;
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

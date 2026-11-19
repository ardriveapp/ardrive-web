import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:cryptography/cryptography.dart';

/// The one way the app asks for the key that opens a private file's data
/// (and its thumbnails): preview, download, zip, thumbnails, sharing and
/// file pages all ask here.
///
/// Today every key comes from the file's drive key, which this device holds
/// for the signed-in profile or, for a visitor, in memory. A private page
/// (publication.json version 3) carries file keys without a drive key; it
/// will add them here, so no reader has to change again.
///
/// Writes that encrypt new metadata (upload, rename, move, hide, license,
/// pin) still derive keys themselves: they need the drive key anyway. The
/// guard test `test/core/crypto/file_keys_guard_test.dart` fails if new code
/// derives a file key anywhere else.
class FileKeys {
  FileKeys({required DriveDao driveDao}) : _driveDao = driveDao;

  final DriveDao _driveDao;

  /// The keys of [driveId]'s files, or null when this device can't open the
  /// drive. [cipherKey] is the signed-in profile's key; a visitor has none,
  /// and their drive key is looked up in memory.
  ///
  /// Asks for the drive key once; for many files of one drive (a zip), get
  /// the ring once and ask it for each file.
  Future<FileKeyRing?> forDrive(
    String driveId, {
    required SecretKey? cipherKey,
  }) async {
    final driveKey = cipherKey != null
        ? await _driveDao.getDriveKey(driveId, cipherKey)
        : await _driveDao.getDriveKeyFromMemory(driveId);
    if (driveKey == null) return null;
    return _DriveKeyRing(_driveDao, driveKey);
  }

  /// The key of one file, or null when this device can't open its drive.
  Future<SecretKey?> keyFor({
    required String driveId,
    required String fileId,
    required SecretKey? cipherKey,
  }) async {
    final ring = await forDrive(driveId, cipherKey: cipherKey);
    return ring?.keyFor(fileId);
  }
}

/// The file keys of one drive.
abstract class FileKeyRing {
  /// The key of [fileId], or null when this ring has none for it.
  Future<SecretKey?> keyFor(String fileId);
}

class _DriveKeyRing implements FileKeyRing {
  _DriveKeyRing(this._driveDao, this._driveKey);

  final DriveDao _driveDao;
  final DriveKey _driveKey;

  @override
  Future<SecretKey?> keyFor(String fileId) =>
      _driveDao.getFileKey(fileId, _driveKey.key);
}

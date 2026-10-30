import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/shared_file_link.dart';
import 'package:arweave/utils.dart' show encodeBytesToBase64;

/// What a file page's share page is told about its file: the version it was
/// published with, pinned, as a v2 share link would tell it.
///
/// A private file's name, size and type are not in [config] and are not here
/// either; the share page shows a plain title until the key in the page's
/// link decrypts the file's metadata (`SharedFileLinkPayload.name`).
SharedFileLinkPayload filePagePayload(PublicationConfig config) {
  final file = config.file!;
  return SharedFileLinkPayload(
    dataTxId: file.dataTxId,
    metadataTxId: file.metadataTxId,
    ownerAddress: config.owner,
    name: file.name,
    size: file.size,
    contentType: file.contentType,
    cipher: file.cipher,
    cipherIv: file.cipherIv,
    isPinned: true,
  );
}

/// A file page's `file` block in `publication.json`: the version it shows.
///
/// A private file's ([cipher] set) name, size and type stay out: they are in
/// its encrypted metadata, which the key in the page's link opens. Its data
/// cipher and IV are not secret; they are on the data transaction's tags.
Map<String, Object> buildFilePageBlock({
  required FileRevision revision,
  ({String cipher, String cipherIv})? cipher,
}) =>
    {
      'dataTxId': revision.dataTxId,
      'metadataTxId': revision.metadataTxId,
      if (cipher == null) ...{
        'name': revision.name,
        'size': revision.size,
        if (revision.dataContentType case final type? when type.isNotEmpty)
          'contentType': type,
      } else ...{
        'cipher': cipher.cipher,
        'cipherIv': cipher.cipherIv,
      },
    };

/// A private file's key, encoded for a link, derived from the drive key the
/// signed-in owner holds; null when this device does not hold it.
Future<String?> fileKeyForLink(
  DriveDao driveDao,
  ProfileState profile, {
  required String driveId,
  required String fileId,
}) async {
  if (profile is! ProfileLoggedIn) return null;
  try {
    final driveKey =
        await driveDao.getDriveKey(driveId, profile.user.cipherKey);
    if (driveKey == null) return null;
    final key = await driveDao.getFileKey(fileId, driveKey.key);
    return encodeBytesToBase64(await key.extractBytes());
  } catch (e) {
    logger.w('[publication] the file key could not be derived: $e');
    return null;
  }
}

/// [page] with a private file's [key] after it, in the fragment: the app's
/// hash route, which never leaves the browser. [page] itself when there is
/// no key.
String withFileKey(String page, String? key) {
  if (key == null) return page;
  final base = page.endsWith('/') ? page : '$page/';
  return '$base#/?${SharedFileLinkParams.key}=$key';
}

/// Whether [link] carries a file key, as [withFileKey] adds it.
bool linkHasKey(String link) =>
    link.contains('#/?${SharedFileLinkParams.key}=');

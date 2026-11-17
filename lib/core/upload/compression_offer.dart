import 'package:ardrive/blocs/upload/models/upload_file.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';

/// Whether the upload review offers "Compress text and code".
///
/// Compression is the person's choice, never a side effect of what is
/// uploaded. It is offered only when it can do something: [switchOn] is
/// `AppConfig.compressDeployments`, the drive is public (a private file is
/// never stored gzipped), and at least one of the [files] is one
/// [CompressionPolicy] would compress.
///
/// [lengths] holds the byte count of each file by `getIdentifier()`. Whether
/// a gzip turns out smaller is only known when it is made, so a file that is
/// eligible may still be sent as it is.
bool offersCompression({
  required bool switchOn,
  required bool isPublic,
  required Iterable<UploadFile> files,
  required Map<String, int> lengths,
}) {
  if (!switchOn || !isPublic) return false;
  for (final file in files) {
    final length = lengths[file.getIdentifier()];
    if (length == null) continue;
    if (CompressionPolicy.isCompressible(
      fileName: file.ioFile.name,
      contentType: file.ioFile.contentType,
      length: length,
    )) {
      return true;
    }
  }
  return false;
}

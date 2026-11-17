import 'package:ardrive/blocs/upload/models/upload_file.dart';

/// Whether [files], a folder upload, is a website being deployed: the picked
/// folder has an `index.html` directly inside it.
///
/// A file's identifier is its path inside the picked folder, with the folder's
/// own name first (`site/index.html`), or the bare name when there is no
/// folder. Only these two shapes are the site root; `site/docs/index.html` on
/// its own is a page of something else.
///
/// Deployments are the only uploads whose text and code are sent gzipped
/// (`CompressionPolicy` in `ardrive_uploader`), so this is what keeps every
/// other upload as it always was.
bool isDeploymentUpload(Iterable<UploadFile> files) {
  for (final file in files) {
    final segments = file.getIdentifier().split('/');
    if (segments.length <= 2 && segments.last == 'index.html') {
      return true;
    }
  }
  return false;
}

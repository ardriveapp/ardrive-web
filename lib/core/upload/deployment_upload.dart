import 'package:ardrive/blocs/upload/models/upload_file.dart';

/// The top-level folders of a folder upload that are websites being
/// deployed: those with an `index.html` directly inside them.
///
/// A file's identifier is its path inside what was picked, with the folder's
/// own name first (`site/index.html`). Only that shape is a site root.
/// `site/docs/index.html` on its own is a page of something else, and a bare
/// `index.html` is a flat selection of files, not a folder: neither counts.
///
/// Deployments are the only uploads whose text and code are sent gzipped
/// (`CompressionPolicy` in `ardrive_uploader`), so this is what keeps every
/// other upload as it always was. Compression is decided per folder: when two
/// folders are dropped and one has a root `index.html`, only the files under
/// that one qualify (see [isInDeployment]).
Set<String> deploymentRoots(Iterable<UploadFile> files) {
  final roots = <String>{};
  for (final file in files) {
    final segments = file.getIdentifier().split('/');
    if (segments.length == 2 && segments.last == 'index.html') {
      roots.add(segments.first);
    }
  }
  return roots;
}

/// Whether [file] lies under one of the [roots] of [deploymentRoots].
bool isInDeployment(UploadFile file, Set<String> roots) {
  final segments = file.getIdentifier().split('/');
  return segments.length >= 2 && roots.contains(segments.first);
}

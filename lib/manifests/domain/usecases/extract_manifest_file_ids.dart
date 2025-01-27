import 'package:ardrive/manifests/domain/entities/manifest.dart';

/// Use case for extracting file IDs from a manifest
class ExtractManifestFileIds {
  /// Returns a list of all file IDs in the manifest
  List<String> call(Manifest manifest) {
    return manifest.fileIds;
  }

  /// Returns a map of file paths to their IDs
  Map<String, String> getFilePathsWithIds(Manifest manifest) {
    return manifest.getFilePathsWithIds();
  }

  /// Gets the ID for a specific file path
  String? getFileIdByPath(Manifest manifest, String path) {
    return manifest.getFileIdByPath(path);
  }
}

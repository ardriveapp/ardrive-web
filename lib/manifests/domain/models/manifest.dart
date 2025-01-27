import 'package:equatable/equatable.dart';

/// Represents a parsed Arweave manifest.
class Manifest extends Equatable {
  /// The manifest type (e.g., 'arweave/paths')
  final String manifest;

  /// The manifest version
  final String version;

  /// The paths mapping in the manifest
  final Map<String, Map<String, dynamic>> paths;

  /// The index file information (optional)
  final Map<String, dynamic>? index;

  /// The fallback file information (optional)
  final Map<String, dynamic>? fallback;

  /// List of file IDs referenced in the manifest
  final List<String> fileIds;

  const Manifest({
    required this.manifest,
    required this.version,
    required this.paths,
    this.index,
    this.fallback,
    required this.fileIds,
  });

  /// Creates a [Manifest] instance from JSON data.
  factory Manifest.fromJson(Map<String, dynamic> json) {
    final paths = Map<String, Map<String, dynamic>>.from(json['paths'] as Map);

    // Extract file IDs from paths
    final fileIds = <String>[];
    for (final pathData in paths.values) {
      if (pathData.containsKey('id')) {
        fileIds.add(pathData['id'] as String);
      }
    }

    return Manifest(
      manifest: json['manifest'] as String,
      version: json['version'] as String,
      paths: paths,
      index: json['index'] != null
          ? Map<String, dynamic>.from(json['index'] as Map)
          : null,
      fallback: json['fallback'] != null
          ? Map<String, dynamic>.from(json['fallback'] as Map)
          : null,
      fileIds: fileIds,
    );
  }

  @override
  List<Object?> get props => [
        manifest,
        version,
        paths,
        index,
        fallback,
        fileIds,
      ];
}

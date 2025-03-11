import 'package:equatable/equatable.dart';

class Manifest extends Equatable {
  final String manifest;
  final String version;
  final Map<String, Map<String, dynamic>> paths;
  final String? index;
  final Map<String, dynamic>? fallback;

  const Manifest({
    required this.manifest,
    required this.version,
    required this.paths,
    this.index,
    this.fallback,
  });

  factory Manifest.fromJson(Map<String, dynamic> json) {
    return Manifest(
      manifest: json['manifest'] as String,
      version: json['version'] as String,
      paths: Map<String, Map<String, dynamic>>.from(
        (json['paths'] as Map<String, dynamic>).map(
          (key, value) => MapEntry(key, value as Map<String, dynamic>),
        ),
      ),
      index: json['index'] != null
          ? (json['index'] is String
              ? json['index'] as String
              : (json['index'] as Map<String, dynamic>)['path'] as String?)
          : null,
      fallback: json['fallback'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'manifest': manifest,
      'version': version,
      'paths': paths,
      if (index != null) 'index': {'path': index},
      if (fallback != null) 'fallback': fallback,
    };
  }

  /// Returns a list of all file IDs in the manifest
  List<String> get fileIds {
    final Set<String> ids = {};

    // Extract IDs from paths
    for (final pathData in paths.values) {
      if (pathData.containsKey('id')) {
        ids.add(pathData['id'] as String);
      }
    }

    // Add index file ID if present
    if (index != null && paths.containsKey(index)) {
      final indexPathData = paths[index!];
      if (indexPathData != null && indexPathData.containsKey('id')) {
        ids.add(indexPathData['id'] as String);
      }
    }

    if (fallback != null) {
      if (fallback!.containsKey('id')) {
        ids.add(fallback!['id'] as String);
      }
    }

    return ids.toList();
  }

  /// Returns a map of file paths to their IDs
  Map<String, String> getFilePathsWithIds() {
    return Map.fromEntries(
      paths.entries
          .where((entry) => entry.value.containsKey('id'))
          .map((entry) => MapEntry(entry.key, entry.value['id'] as String)),
    );
  }

  /// Gets the ID for a specific file path
  String? getFileIdByPath(String path) {
    final fileInfo = paths[path];
    return fileInfo?['id'] as String?;
  }

  @override
  List<Object?> get props => [manifest, version, paths, index, fallback];
}

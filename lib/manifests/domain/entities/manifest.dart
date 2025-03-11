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

  @override
  List<Object?> get props => [manifest, version, paths, index, fallback];
}

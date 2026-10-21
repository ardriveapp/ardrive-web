import 'dart:convert';

import 'package:ardrive/core/arfs/repository/file_repository.dart';
import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:collection/collection.dart';
import 'package:drift/drift.dart' show Uint8List;
import 'package:json_annotation/json_annotation.dart'
    show JsonKey, JsonSerializable;
import 'package:package_info_plus/package_info_plus.dart';

part 'manifest_data.g.dart';

@JsonSerializable()
class ManifestIndex {
  @JsonKey()
  final String path;

  ManifestIndex(this.path);

  factory ManifestIndex.fromJson(Map<String, dynamic> json) =>
      _$ManifestIndexFromJson(json);
  Map<String, dynamic> toJson() => _$ManifestIndexToJson(this);
}

@JsonSerializable()
class ManifestPath {
  @JsonKey()
  final String id;
  @JsonKey(includeFromJson: false, includeToJson: false)
  final String? fileId;

  ManifestPath(
    this.id, {
    this.fileId,
  });

  factory ManifestPath.fromJson(Map<String, dynamic> json) =>
      _$ManifestPathFromJson(json);
  Map<String, dynamic> toJson() => _$ManifestPathToJson(this);
}

@JsonSerializable()
class ManifestFallback {
  final String id;

  ManifestFallback(this.id);

  factory ManifestFallback.fromJson(Map<String, dynamic> json) =>
      ManifestFallback(json['fallback']['id'] as String);

  Map<String, dynamic> toJson() => {'id': id};
}

@JsonSerializable(explicitToJson: true)
class ManifestData {
  @JsonKey()
  String manifest = 'arweave/paths';
  @JsonKey()
  String version = '0.2.0';
  @JsonKey(includeIfNull: false)
  final ManifestFallback? fallback;
  @JsonKey()
  final ManifestIndex index;
  @JsonKey()
  final Map<String, ManifestPath> paths;

  ManifestData(
    this.index,
    this.paths, {
    this.fallback,
  });

  int get size => jsonData.lengthInBytes;
  Uint8List get jsonData => utf8.encode(json.encode(this));

  Future<DataItem> asPreparedDataItem({
    required ArweaveAddressString owner,
  }) async {
    logger.d(json.encode(this));

    final manifestDataItem = DataItem.withBlobData(data: jsonData)
      ..setOwner(owner)
      ..addApplicationTags(
        version: (await PackageInfo.fromPlatform()).version,
      )
      ..addTag(EntityTag.contentType, ContentType.manifest);

    return manifestDataItem;
  }

  factory ManifestData.fromJson(Map<String, dynamic> json) =>
      _$ManifestDataFromJson(json);
  Map<String, dynamic> toJson() => _$ManifestDataToJson(this);
}

/// Removes the base path of the target folder and replaces spaces with
/// underscores, which keeps published URLs free of `%20`.
///
/// Gateways decode a request's path before matching it against a manifest's
/// keys, so the underscores are a convention rather than a requirement, which
/// is what lets [assignManifestPaths] fall back to a raw path on a collision.
String prepareManifestPath({
  required String filePath,
  required String rootFolderPath,
}) {
  return filePath.substring(rootFolderPath.length + 1).replaceAll(' ', '_');
}

/// Thrown when a folder holds nothing a manifest could publish: every file
/// under it is hidden, inside a hidden folder, or itself a manifest.
class ManifestHasNoFilesException implements Exception {
  ManifestHasNoFilesException(this.folderId);

  final String folderId;

  @override
  String toString() =>
      'ManifestHasNoFilesException: folder $folderId has no file to publish';
}

class ManifestDataBuilder {
  final FolderRepository folderRepository;
  final FileRepository fileRepository;

  ManifestDataBuilder({
    required this.folderRepository,
    required this.fileRepository,
  });

  Future<ManifestData> build({
    required FolderNode folderNode,
    String? fallbackTxId,
  }) async {
    final fileList = _publishableFiles(folderNode);

    if (fileList.isEmpty) {
      throw ManifestHasNoFilesException(folderNode.folder.id);
    }

    // Link the index to an index.html in the root folder, otherwise to the
    // first file. Chosen from the files being published, so a hidden
    // index.html can never become an index that no path serves.
    final indexFile = folderNode.files.values
            .where(_isPublishable)
            .firstWhereOrNull((f) => f.name == 'index.html') ??
        fileList.first;

    final rootFolderPath = await folderRepository.getFolderPath(
      folderNode.folder.driveId,
      folderNode.folder.id,
    );

    final entries = [
      for (final file in fileList)
        await _pathsOf(file, rootFolderPath: rootFolderPath),
    ];

    final keys = assignManifestPaths(entries);

    final index = ManifestIndex(keys[indexFile.id]!);

    final paths = {
      for (final file in fileList)
        keys[file.id]!: ManifestPath(file.dataTxId, fileId: file.id)
    };

    final fallback =
        fallbackTxId != null ? ManifestFallback(fallbackTxId) : null;

    return ManifestData(
      index,
      paths,
      fallback: fallback,
    );
  }

  Future<ManifestPathCandidate> _pathsOf(
    FileEntry file, {
    required String rootFolderPath,
  }) async {
    final filePath = await fileRepository.getFilePath(file.driveId, file.id);
    return (
      file: file,
      rawPath: filePath.substring(rootFolderPath.length + 1),
      preparedPath: prepareManifestPath(
        filePath: filePath,
        rootFolderPath: rootFolderPath,
      ),
    );
  }
}

/// A file with the two paths it could be published at: as named, and as
/// [prepareManifestPath] writes it.
typedef ManifestPathCandidate = ({
  FileEntry file,
  String rawPath,
  String preparedPath,
});

bool _isPublishable(FileEntry file) =>
    file.dataContentType != ContentType.manifest && !file.isHidden;

/// Every file a manifest of [node] publishes, root files first.
///
/// A hidden folder hides everything under it, however deep. Hiding a folder
/// marks that folder alone and never its contents, so a filter on each file's
/// own flag publishes a hidden folder's files at their real paths.
List<FileEntry> _publishableFiles(FolderNode node) => [
      ...node.files.values.where(_isPublishable),
      for (final subfolder in node.subfolders)
        if (!subfolder.folder.isHidden) ..._publishableFiles(subfolder),
    ];

/// Chooses one manifest path per file, keyed by file id, so that no file is
/// lost to another file's path.
///
/// A path's spaces become underscores, which keeps published URLs free of
/// `%20` and is what every manifest so far has done ([prepareManifestPath]). Two names can then
/// arrive at one path: `my file.txt` and `my_file.txt`. The paths map keeps
/// one entry per key, so one of the two files was silently dropped.
///
/// Gateways decode a request's path before matching it against the
/// manifest's keys, so a raw path with its spaces is a valid key in its own
/// right. On a collision every file takes its raw path, which leaves the
/// underscored path with the file whose name it already was. A file that
/// collides with nobody keeps the underscored path it has always had, so an
/// existing URL stays where it was.
///
/// Two files with exactly the same path are told apart by their ids, the
/// earliest created keeping the plain path.
Map<String, String> assignManifestPaths(
  List<ManifestPathCandidate> entries,
) {
  final claimants = <String, int>{};
  for (final e in entries) {
    claimants[e.preparedPath] = (claimants[e.preparedPath] ?? 0) + 1;
  }

  final chosen = {
    for (final e in entries)
      e.file.id: claimants[e.preparedPath] == 1 ? e.preparedPath : e.rawPath,
  };

  final byKey = <String, List<FileEntry>>{};
  for (final e in entries) {
    byKey.putIfAbsent(chosen[e.file.id]!, () => []).add(e.file);
  }

  for (final MapEntry(key: key, value: files) in byKey.entries) {
    if (files.length < 2) continue;
    files.sort((a, b) {
      final byDate = a.dateCreated.compareTo(b.dateCreated);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    for (final file in files.skip(1)) {
      chosen[file.id] = _withIdSuffix(key, file.id);
    }
  }

  return chosen;
}

/// `photos/beach.jpg` becomes `photos/beach~3f9a1c2e.jpg`, keeping the
/// extension last so tools that read it still find it.
String _withIdSuffix(String path, String fileId) {
  final tag = '~${fileId.length > 8 ? fileId.substring(0, 8) : fileId}';
  final slash = path.lastIndexOf('/');
  final dot = path.lastIndexOf('.');
  return dot > slash + 1
      ? '${path.substring(0, dot)}$tag${path.substring(dot)}'
      : '$path$tag';
}

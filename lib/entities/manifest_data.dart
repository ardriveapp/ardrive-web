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

/// Utility function to remove base path of the target folder and
/// replace spaces with underscores for arweave.net URL compatibility
String prepareManifestPath({
  required String filePath,
  required String rootFolderPath,
}) {
  return filePath.substring(rootFolderPath.length + 1).replaceAll(' ', '_');
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
    final fileList = folderNode
        .getRecursiveFiles()
        // We will not include any existing manifests in the new manifest
        // We will not include any hidden files in the new manifest
        .where((f) => f.dataContentType != ContentType.manifest && !f.isHidden);

    final indexFile = () {
      final indexHtml = folderNode.files.values.firstWhereOrNull(
        (f) => f.name == 'index.html',
      );

      if (indexHtml != null) {
        // Link index field to any index.html file that exists in the root folder
        return indexHtml;
      }

      // Otherwise link it to the first file in the folder
      return fileList.first;
    }();

    final rootFolderPath = await folderRepository.getFolderPath(
      folderNode.folder.driveId,
      folderNode.folder.id,
    );

    final indexPath =
        await fileRepository.getFilePath(indexFile.driveId, indexFile.id);

    final index = ManifestIndex(
      prepareManifestPath(filePath: indexPath, rootFolderPath: rootFolderPath),
    );

    final paths = {
      for (final file in fileList)
        prepareManifestPath(
          filePath: await fileRepository.getFilePath(file.driveId, file.id),
          rootFolderPath: rootFolderPath,
        ): ManifestPath(file.dataTxId, fileId: file.id)
    };

    return ManifestData(
      index,
      paths,
      fallback: fallbackTxId != null ? ManifestFallback(fallbackTxId) : null,
    );
  }
}

import 'dart:convert';

import 'package:ardrive/utils/logger/logger.dart';

const Map<String, List<String>> reservedFieldsPerEntityType = {
  'drive': ['name', 'rootFolderId'],
  'folder': ['name'],
  'file': ['name', 'size', 'lastModifiedDate', 'dataTxId', 'dataContentType'],
  'test': ['reserved'],
};

String extractCustomMetadataForEntityType(
  Map<String, dynamic> metadata, {
  required String entityType,
}) {
  if (!reservedFieldsPerEntityType.containsKey(entityType)) {
    throw Exception('Bad entity type: $entityType');
  }

  final reservedFields = reservedFieldsPerEntityType[entityType]!;

  metadata.removeWhere((key, value) => reservedFields.contains(key));
  final customMetadataAsString = json.encode(metadata);
  logger.d('Custom metadata for $entityType: $customMetadataAsString');
  return customMetadataAsString;
}

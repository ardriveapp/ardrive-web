import 'dart:convert';

import 'package:ardrive/utils/logger/logger.dart';

String Function() customMetadataFactory(
  Map<String, dynamic> metadata,
  List<String> reservedFields, {
  String entityType = 'entity',
}) {
  return () {
    metadata.removeWhere((key, value) => reservedFields.contains(key));
    final customMetadataAsString = json.encode(metadata);
    logger.d('Custom metadata for $entityType: $customMetadataAsString');
    return customMetadataAsString;
  };
}

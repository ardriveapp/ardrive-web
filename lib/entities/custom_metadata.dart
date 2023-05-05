import 'dart:convert';

String Function() customMetadataFactory(
  Map<String, dynamic> metadata,
  List<String> reservedFields,
) {
  return () {
    metadata.removeWhere((key, value) => reservedFields.contains(key));
    return json.encode(metadata);
  };
}

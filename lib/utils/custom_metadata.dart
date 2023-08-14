import 'dart:convert';

import 'package:arweave/arweave.dart';

Map<String, dynamic>? parseCustomJsonMetadata(String? customJsonMetadata) {
  if (customJsonMetadata == null) {
    return null;
  }
  return jsonDecode(customJsonMetadata);
}

List<Tag>? parseCustomGqlTags(String? customGQLTags) {
  if (customGQLTags == null) {
    return null;
  }
  return (jsonDecode(customGQLTags) as List<dynamic>)
      .map((jsonTag) => Tag.fromJson(jsonTag))
      .toList();
}

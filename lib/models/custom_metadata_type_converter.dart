import 'dart:convert';

import 'package:ardrive/models/custom_metadata_type.dart';
import 'package:drift/drift.dart';

class CustomMetadataTypeConverter
    extends TypeConverter<CustomMetadata?, String?> {
  const CustomMetadataTypeConverter();

  @override
  CustomMetadata? mapToDart(String? fromDb) {
    if (fromDb == null) {
      return null;
    }
    return CustomMetadata.fromJson(json.decode(fromDb));
  }

  @override
  String? mapToSql(CustomMetadata? value) {
    if (value == null) {
      return null;
    }
    return json.encode(value);
  }
}

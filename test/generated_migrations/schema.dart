// GENERATED CODE, DO NOT EDIT BY HAND.
// ignore_for_file: type=lint
//@dart=2.12
import 'package:drift/drift.dart';
import 'package:drift/internal/migrations.dart';

import 'schema_v17.dart' as v17;
import 'schema_v18.dart' as v18;
import 'schema_v19.dart' as v19;

class GeneratedHelper implements SchemaInstantiationHelper {
  @override
  GeneratedDatabase databaseForVersion(QueryExecutor db, int version) {
    switch (version) {
      case 17:
        return v17.DatabaseAtV17(db);
      case 18:
        return v18.DatabaseAtV18(db);
      case 19:
        return v19.DatabaseAtV19(db);
      default:
        throw MissingSchemaException(version, const {17, 18, 19});
    }
  }
}

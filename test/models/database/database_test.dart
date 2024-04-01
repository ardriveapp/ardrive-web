@Skip('Skip migration tests for now')
import 'package:ardrive/models/database/database.dart';
import 'package:drift_dev/api/migrations.dart';
import 'package:test/test.dart';

import '../../generated_migrations/schema.dart';

void main() {
  // Initialize SchemaVerifier before all tests
  late SchemaVerifier verifier;

  setUpAll(() {
    // Initializes SchemaVerifier with GeneratedHelper from drift
    verifier = SchemaVerifier(GeneratedHelper());
  });

  // Utility function to setup database and run migration to a target version
  // It returns a Database instance for further validation in tests.
  Future<Database> migrateDatabase(
      SchemaVerifier verifier, int startVersion, int targetVersion) async {
    final connection = await verifier.startAt(startVersion);
    final db = Database(connection);
    await verifier.migrateAndValidate(db, targetVersion);
    return db;
  }

  group('Database Migration Tests', () {
    test('should successfully upgrade database schema from v17 to v19',
        () async {
      // Executes migration from version 17 to 19 and validates the schema
      final db = await migrateDatabase(verifier, 17, 19);

      db.close();
    });

    test('should successfully upgrade database schema from v18 to v19',
        () async {
      // Executes migration from version 18 to 19 and validates the schema
      final db = await migrateDatabase(verifier, 18, 19);

      db.close();
    });
  });
}

import 'package:ardrive/models/database/migration_strategy/resolve_migration.dart';
import 'package:ardrive/models/database/migration_strategy/strategies/migration_default.dart';
import 'package:ardrive/models/database/migration_strategy/strategies/migration_v16_to_v17.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveMigration method', () {
    test('fallbacks to default migration', () {
      final migration = resolveMigration(1, 2);
      expect(migration, onUpgradeReCreate);
    });

    test('fallbacks to default migration when forced', () {
      final migration = resolveMigration(16, 17, forceFallbackToDefault: true);
      expect(migration, onUpgradeReCreate);
    });

    test('returns v16 to v17 migration', () {
      final migration = resolveMigration(16, 17);
      expect(migration, onUpgradeV16ToV17);
    });
  });
}

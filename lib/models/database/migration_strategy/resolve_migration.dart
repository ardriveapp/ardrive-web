import 'package:ardrive/models/database/migration_strategy/strategies/migration_default.dart';
import 'package:ardrive/models/database/migration_strategy/strategies/migration_v16_to_v17.dart';
import 'package:ardrive/models/database/migration_strategy/types.dart';
import 'package:flutter/foundation.dart';

CustomOnUpgrade resolveMigration(
  int from,
  int to, {
  bool forceFallbackToDefault = false,
}) {
  if (forceFallbackToDefault) {
    return _fallbackToDefault(from, to);
  }

  if (from == 16 && to == 17) {
    debugPrint('Migrating schema from v16 to v17');
    return onUpgradeV16ToV17;
  }

  return _fallbackToDefault(from, to);
}

CustomOnUpgrade _fallbackToDefault(
  int from,
  int to,
) =>
    (allTables, m, from, to) async {
      debugPrint(
        'WARNING: Fallbacking to default DB migration: drop and re-create all'
        ' tables - from v$from to v$to',
      );
      return onUpgradeDefault(allTables, m, from, to);
    };

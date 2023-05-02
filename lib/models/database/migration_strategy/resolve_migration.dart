import 'package:ardrive/models/database/migration_strategy/strategies/migration_default.dart';
import 'package:ardrive/models/database/migration_strategy/strategies/migration_v16_to_v17.dart';
import 'package:ardrive/models/database/migration_strategy/types.dart';

CustomOnUpgrade resolveMigration(
  int from,
  int to, {
  bool forceFallbackToDefault = false,
}) {
  if (forceFallbackToDefault) {
    return onUpgradeDefault;
  }

  if (from == 16 && to == 17) {
    return onUpgradeV16ToV17;
  }

  return onUpgradeDefault;
}

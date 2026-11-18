import 'package:collection/collection.dart' show IterableExtension;
import 'package:ardrive_utils/ardrive_utils.dart';

export 'graphql_api.dart';

import 'graphql_api.dart';

extension TransactionMixinExtensions on TransactionCommonMixin {
  String? getTag(String tagName) =>
      tags.firstWhereOrNull((t) => t.name == tagName)?.value;

  DateTime getCommitTime() {
    final unixTimeValue = int.parse(getTag(EntityTag.unixTime)!);
    
    // Check if the value is abnormally large (likely already in milliseconds)
    // Unix timestamp in seconds for year 2100 is ~4102444800
    // If value > 10000000000 (Nov 2286 in seconds), it's likely milliseconds
    final isAlreadyMilliseconds = unixTimeValue > 10000000000;
    
    final milliseconds = isAlreadyMilliseconds ? unixTimeValue : unixTimeValue * 1000;

    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }
}

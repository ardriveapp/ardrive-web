import 'package:collection/collection.dart' show IterableExtension;
import 'package:ardrive_utils/ardrive_utils.dart';

export 'graphql_api.dart';

import 'graphql_api.dart';

extension TransactionMixinExtensions on TransactionCommonMixin {
  String? getTag(String tagName) =>
      tags.firstWhereOrNull((t) => t.name == tagName)?.value;

  DateTime getCommitTime() {
    final unixTimeStr = getTag(EntityTag.unixTime)!;
    final milliseconds = getTag(EntityTag.arFs) != '0.10'
        ? (double.parse(unixTimeStr) * 1000).round()
        : double.parse(unixTimeStr).round();

    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }
}

import 'package:collection/collection.dart' show IterableExtension;
import 'package:ardrive_utils/ardrive_utils.dart';

export 'graphql_api.dart';

import 'graphql_api.dart';

extension TransactionMixinExtensions on TransactionCommonMixin {
  String? getTag(String tagName) =>
      tags.firstWhereOrNull((t) => t.name == tagName)?.value;

  DateTime getCommitTime() {
    final milliseconds = getTag(EntityTag.arFs) != '0.10'
        ? int.parse(getTag(EntityTag.unixTime)!) * 1000
        : int.parse(getTag(EntityTag.unixTime)!);

    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }
}

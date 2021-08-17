import 'package:ardrive/entities/entities.dart';

import 'graphql_api.dart';

export 'graphql_api.dart';

extension TransactionMixinExtensions on TransactionCommonMixin {
  String getTag(String tagName) {
    try {
      return tags.firstWhere((t) => t.name == tagName).value;
    } catch (e) {
      return '';
    }
  }

  DateTime getCommitTime() {
    final milliseconds = getTag(EntityTag.arFs) != '0.10'
        ? int.parse(getTag(EntityTag.unixTime)) * 1000
        : int.parse(getTag(EntityTag.unixTime));

    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }
}
